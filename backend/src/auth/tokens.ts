import { SignJWT, jwtVerify, createRemoteJWKSet, type JWTVerifyGetKey } from "jose";

/**
 * Subjects are either an anonymous install ("install:<uuid>") or a Sign in
 * with Apple user ("apple:<sub>"). Guest usage works without an account.
 */
export type Subject = `install:${string}` | `apple:${string}`;

const ISSUER = "languify";
const AUDIENCE = "languify-app";
export const TOKEN_TTL_SECONDS = 30 * 24 * 60 * 60;

export class TokenService {
  private readonly key: Uint8Array;

  constructor(secret: string) {
    this.key = new TextEncoder().encode(secret);
  }

  async issue(subject: Subject, now = new Date()): Promise<{ token: string; expiresAt: Date }> {
    const expiresAt = new Date(now.getTime() + TOKEN_TTL_SECONDS * 1000);
    const token = await new SignJWT({})
      .setProtectedHeader({ alg: "HS256" })
      .setSubject(subject)
      .setIssuer(ISSUER)
      .setAudience(AUDIENCE)
      .setIssuedAt(Math.floor(now.getTime() / 1000))
      .setExpirationTime(Math.floor(expiresAt.getTime() / 1000))
      .sign(this.key);
    return { token, expiresAt };
  }

  async verify(token: string): Promise<Subject | null> {
    try {
      const { payload } = await jwtVerify(token, this.key, { issuer: ISSUER, audience: AUDIENCE, algorithms: ["HS256"] });
      const sub = payload.sub ?? "";
      return sub.startsWith("install:") || sub.startsWith("apple:") ? (sub as Subject) : null;
    } catch {
      return null;
    }
  }
}

/** Verifies Sign in with Apple identity tokens against Apple's published keys. */
export class AppleIdentityVerifier {
  private readonly jwks: JWTVerifyGetKey;

  constructor(
    private readonly bundleId: string,
    jwks?: JWTVerifyGetKey,
  ) {
    this.jwks = jwks ?? createRemoteJWKSet(new URL("https://appleid.apple.com/auth/keys"));
  }

  async verify(identityToken: string): Promise<string | null> {
    try {
      const { payload } = await jwtVerify(identityToken, this.jwks, {
        issuer: "https://appleid.apple.com",
        audience: this.bundleId,
      });
      return typeof payload.sub === "string" && payload.sub.length > 0 ? payload.sub : null;
    } catch {
      return null;
    }
  }
}
