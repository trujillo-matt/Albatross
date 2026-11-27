// Apple Push Notification service: a signed token and one request per device.
const b64url = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

/** The provider token APNs wants: ES256 over the team and key ids, signed with the .p8 key from the Apple developer account. */
export async function providerToken(keyP8: string, keyId: string, teamId: string): Promise<string> {
  const pem = keyP8.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const enc = new TextEncoder();
  const header = b64url(enc.encode(JSON.stringify({ alg: "ES256", kid: keyId })));
  const claims = b64url(enc.encode(JSON.stringify({ iss: teamId, iat: Math.floor(Date.now() / 1000) })));
  const signature = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, enc.encode(`${header}.${claims}`)));
  return `${header}.${claims}.${b64url(signature)}`;
}

export interface PushResult { ok: boolean; status: number; reason?: string; gone?: boolean }

/** Sends one alert. A phone built for development has a sandbox token and a store build a production one, so both hosts are tried. */
export async function sendAlert(
  token: string, jwt: string, bundleId: string,
  alert: { title: string; body: string }, data: Record<string, string>, collapseId: string,
): Promise<PushResult> {
  const payload = JSON.stringify({ aps: { alert, sound: "default", "thread-id": data.tournament_id }, ...data });
  let last: PushResult = { ok: false, status: 0 };
  for (const host of ["api.push.apple.com", "api.sandbox.push.apple.com"]) {
    const res = await fetch(`https://${host}/3/device/${token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${jwt}`, "apns-topic": bundleId, "apns-push-type": "alert",
        "apns-priority": "10", "apns-collapse-id": collapseId,
      },
      body: payload,
    });
    if (res.ok) return { ok: true, status: res.status };
    const reason = (await res.json().catch(() => ({})))?.reason as string | undefined;
    last = { ok: false, status: res.status, reason, gone: res.status === 410 || reason === "Unregistered" };
    // BadDeviceToken from one host usually means the token belongs to the other one.
    if (reason !== "BadDeviceToken") break;
  }
  return last;
}
