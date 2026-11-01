import http2 from "node:http2";
import jwt from "jsonwebtoken";

// Apple Push Notification service (token-based auth with a .p8 key).
// Disabled -- every send is a no-op -- until these are set on the server:
//   APNS_KEY_ID      Key ID shown next to the key in the Apple Developer portal
//   APNS_TEAM_ID     Your 10-character Team ID
//   APNS_KEY         Contents of the AuthKey_XXXX.p8 file (newlines may be "\n")
//   APNS_BUNDLE_ID   The app's bundle id (defaults to com.personal.aura)

const keyId = process.env.APNS_KEY_ID ?? "";
const teamId = process.env.APNS_TEAM_ID ?? "";
const privateKey = (process.env.APNS_KEY ?? "").replace(/\\n/g, "\n");
const bundleId = process.env.APNS_BUNDLE_ID ?? "com.personal.aura";

export const pushEnabled = keyId.length > 0 && teamId.length > 0 && privateKey.includes("PRIVATE KEY");

export type PushEnvironment = "production" | "sandbox";

export interface PushMessage {
  title: string;
  body: string;
  groupId: string;
}

let cachedToken: { value: string; issuedAt: number } | null = null;

function providerToken() {
  const now = Math.floor(Date.now() / 1000);
  // Apple rejects tokens older than an hour and throttles ones refreshed
  // more often than every 20 minutes.
  if (cachedToken && now - cachedToken.issuedAt < 45 * 60) {
    return cachedToken.value;
  }
  const value = jwt.sign({ iss: teamId, iat: now }, privateKey, {
    algorithm: "ES256",
    header: { alg: "ES256", kid: keyId }
  });
  cachedToken = { value, issuedAt: now };
  return value;
}

/// Sends one notification. Resolves to "gone" when Apple says the token is no
/// longer valid, so the caller can forget it.
function sendOne(deviceToken: string, environment: PushEnvironment, message: PushMessage): Promise<"ok" | "gone" | "error"> {
  const host = environment === "sandbox" ? "https://api.sandbox.push.apple.com" : "https://api.push.apple.com";
  return new Promise((resolve) => {
    let client: http2.ClientHttp2Session;
    try {
      client = http2.connect(host);
    } catch {
      resolve("error");
      return;
    }
    client.on("error", () => resolve("error"));
    const body = JSON.stringify({
      aps: { alert: { title: message.title, body: message.body }, sound: "default", "content-available": 1 },
      groupId: message.groupId
    });
    const request = client.request({
      ":method": "POST",
      ":path": `/3/device/${deviceToken}`,
      authorization: `bearer ${providerToken()}`,
      "apns-topic": bundleId,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "content-type": "application/json"
    });
    let status = 0;
    let responseBody = "";
    request.on("response", (headers) => {
      status = Number(headers[":status"] ?? 0);
    });
    request.setEncoding("utf8");
    request.on("data", (chunk) => {
      responseBody += chunk;
    });
    request.on("end", () => {
      client.close();
      if (status === 200) {
        resolve("ok");
      } else if (status === 410 || responseBody.includes("BadDeviceToken") || responseBody.includes("Unregistered")) {
        resolve("gone");
      } else {
        console.error(`APNs ${status}: ${responseBody}`);
        resolve("error");
      }
    });
    request.on("error", () => {
      client.close();
      resolve("error");
    });
    request.end(body);
  });
}

export async function sendPush(
  devices: Array<{ token: string; environment: PushEnvironment }>,
  message: PushMessage
): Promise<string[]> {
  if (!pushEnabled || devices.length === 0) {
    return [];
  }
  const results = await Promise.all(devices.map((device) => sendOne(device.token, device.environment, message)));
  return devices.filter((_, index) => results[index] === "gone").map((device) => device.token);
}
