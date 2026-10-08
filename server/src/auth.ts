import { createRemoteJWKSet, jwtVerify, SignJWT, type JWTVerifyGetKey } from "jose";

export type Provider = "apple" | "google";

export interface VerifiedIdentity {
  provider: Provider;
  subject: string;
}

const APPLE_ISSUER = "https://appleid.apple.com";
const GOOGLE_ISSUERS = ["https://accounts.google.com", "accounts.google.com"];

// Module scope so the key sets are cached across requests in one isolate.
const appleKeys = createRemoteJWKSet(new URL("https://appleid.apple.com/auth/keys"));
const googleKeys = createRemoteJWKSet(new URL("https://www.googleapis.com/oauth2/v3/certs"));

export interface IdentityConfig {
  appleBundleID: string;
  googleClientID: string;
  // Overridable in tests.
  appleKeys?: JWTVerifyGetKey;
  googleKeys?: JWTVerifyGetKey;
}

export async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/**
 * Verifies a provider ID token. The app generates a random nonce, sends its
 * SHA-256 to the provider, and sends the raw nonce here, so a token captured
 * from another sign-in cannot be replayed.
 */
export async function verifyIdentityToken(
  provider: Provider,
  idToken: string,
  rawNonce: string,
  config: IdentityConfig,
): Promise<VerifiedIdentity> {
  if (provider === "apple") {
    const { payload } = await jwtVerify(idToken, config.appleKeys ?? appleKeys, {
      issuer: APPLE_ISSUER,
      audience: config.appleBundleID,
    });
    if (payload.nonce !== (await sha256Hex(rawNonce))) throw new AuthError("nonce mismatch");
    if (!payload.sub) throw new AuthError("missing subject");
    return { provider, subject: payload.sub };
  }

  if (!config.googleClientID) throw new AuthError("google sign-in is not configured");
  const { payload } = await jwtVerify(idToken, config.googleKeys ?? googleKeys, {
    issuer: GOOGLE_ISSUERS,
    audience: config.googleClientID,
  });
  // Google echoes the nonce sent in the authorization request as-is.
  if (payload.nonce !== (await sha256Hex(rawNonce))) throw new AuthError("nonce mismatch");
  if (!payload.sub) throw new AuthError("missing subject");
  return { provider, subject: payload.sub };
}

const SESSION_ISSUER = "studyplanner-api";
const SESSION_TTL_SECONDS = 60 * 60 * 24 * 30;

function sessionKey(secret: string) {
  if (secret.length < 32) throw new Error("SESSION_SECRET must be at least 32 characters");
  return new TextEncoder().encode(secret);
}

export async function issueSession(userID: string, secret: string): Promise<{ token: string; expiresAt: number }> {
  const expiresAt = Math.floor(Date.now() / 1000) + SESSION_TTL_SECONDS;
  const token = await new SignJWT({})
    .setProtectedHeader({ alg: "HS256" })
    .setSubject(userID)
    .setIssuer(SESSION_ISSUER)
    .setIssuedAt()
    .setExpirationTime(expiresAt)
    .sign(sessionKey(secret));
  return { token, expiresAt };
}

export async function verifySession(token: string, secret: string): Promise<string> {
  const { payload } = await jwtVerify(token, sessionKey(secret), {
    issuer: SESSION_ISSUER,
    algorithms: ["HS256"],
  });
  if (!payload.sub) throw new AuthError("missing subject");
  return payload.sub;
}

export class AuthError extends Error {}
