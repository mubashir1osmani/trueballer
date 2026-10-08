import { createLocalJWKSet, exportJWK, generateKeyPair, SignJWT } from "jose";
import { beforeAll, describe, expect, it } from "vitest";
import { issueSession, sha256Hex, verifyIdentityToken, verifySession } from "../src/auth";
import { planFor } from "../src/plans";

const BUNDLE = "com.mubashir.StudyPlanner";
const GOOGLE_CLIENT = "123.apps.googleusercontent.com";
const SECRET = "test-secret-test-secret-test-secret-123";

let privateKey: CryptoKey;
let keys: ReturnType<typeof createLocalJWKSet>;

beforeAll(async () => {
  const pair = await generateKeyPair("RS256");
  privateKey = pair.privateKey;
  const jwk = { ...(await exportJWK(pair.publicKey)), kid: "k1", alg: "RS256" };
  keys = createLocalJWKSet({ keys: [jwk] });
});

async function token(claims: Record<string, unknown>, issuer: string, audience: string, expires = "5m") {
  return new SignJWT(claims)
    .setProtectedHeader({ alg: "RS256", kid: "k1" })
    .setIssuer(issuer)
    .setAudience(audience)
    .setSubject("user-123")
    .setIssuedAt()
    .setExpirationTime(expires)
    .sign(privateKey);
}

const config = () => ({ appleBundleID: BUNDLE, googleClientID: GOOGLE_CLIENT, appleKeys: keys, googleKeys: keys });

describe("Apple identity tokens", () => {
  it("accepts a token with the right issuer, audience and hashed nonce", async () => {
    const raw = "raw-nonce-0123456789";
    const t = await token({ nonce: await sha256Hex(raw) }, "https://appleid.apple.com", BUNDLE);
    await expect(verifyIdentityToken("apple", t, raw, config())).resolves.toEqual({ provider: "apple", subject: "user-123" });
  });

  it("rejects a replayed token whose nonce does not match", async () => {
    const t = await token({ nonce: await sha256Hex("someone-elses-nonce") }, "https://appleid.apple.com", BUNDLE);
    await expect(verifyIdentityToken("apple", t, "raw-nonce-0123456789", config())).rejects.toThrow();
  });

  it("rejects a token issued for a different app", async () => {
    const raw = "raw-nonce-0123456789";
    const t = await token({ nonce: await sha256Hex(raw) }, "https://appleid.apple.com", "com.other.app");
    await expect(verifyIdentityToken("apple", t, raw, config())).rejects.toThrow();
  });

  it("rejects an expired token", async () => {
    const raw = "raw-nonce-0123456789";
    const t = await token({ nonce: await sha256Hex(raw) }, "https://appleid.apple.com", BUNDLE, "-1m");
    await expect(verifyIdentityToken("apple", t, raw, config())).rejects.toThrow();
  });
});

describe("Google identity tokens", () => {
  it("accepts a token for the configured client", async () => {
    const raw = "raw-nonce-0123456789";
    const t = await token({ nonce: await sha256Hex(raw) }, "https://accounts.google.com", GOOGLE_CLIENT);
    await expect(verifyIdentityToken("google", t, raw, config())).resolves.toMatchObject({ provider: "google" });
  });

  it("refuses when Google sign-in is not configured", async () => {
    const raw = "raw-nonce-0123456789";
    const t = await token({ nonce: await sha256Hex(raw) }, "https://accounts.google.com", GOOGLE_CLIENT);
    await expect(verifyIdentityToken("google", t, raw, { ...config(), googleClientID: "" })).rejects.toThrow();
  });

  it("does not accept an Apple-issued token as Google", async () => {
    const raw = "raw-nonce-0123456789";
    const t = await token({ nonce: await sha256Hex(raw) }, "https://appleid.apple.com", GOOGLE_CLIENT);
    await expect(verifyIdentityToken("google", t, raw, config())).rejects.toThrow();
  });
});

describe("app sessions", () => {
  it("round-trips the user id and rejects a token signed with another secret", async () => {
    const { token: t } = await issueSession("u1", SECRET);
    await expect(verifySession(t, SECRET)).resolves.toBe("u1");
    await expect(verifySession(t, "another-secret-another-secret-12345")).rejects.toThrow();
  });
});

describe("plans", () => {
  it("falls back to free for unknown or expired plans", () => {
    expect(planFor("pro", null).model).toBe("claude-opus-5-5");
    expect(planFor("pro", 1).id).toBe("free");
    expect(planFor("hacker", null).id).toBe("free");
    expect(planFor(null, null).model).toBe("claude-haiku-4-5");
  });
});
