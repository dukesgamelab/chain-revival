/**
 * Server-side Supabase JWT verification.
 *
 * Supports both HS256 (HMAC) and ES256 (ECDSA) tokens.
 * - HS256: uses SUPABASE_JWT_SECRET env var
 * - ES256: fetches the public key from Supabase JWKS endpoint at startup
 *
 * The Supabase project URL is read from SUPABASE_URL env var.
 */

import { createHmac, createVerify, createPublicKey, type KeyObject } from "node:crypto";

const JWT_SECRET = process.env.SUPABASE_JWT_SECRET ?? "";
const SUPABASE_URL = process.env.SUPABASE_URL ?? "";

// ---------------------------------------------------------------------------
// JWKS cache for ES256 verification
// ---------------------------------------------------------------------------

interface JwkEntry {
  kty: string;
  crv?: string;
  x?: string;
  y?: string;
  kid?: string;
  alg?: string;
  use?: string;
}

/** kid -> KeyObject cache, populated at startup */
const jwksCache = new Map<string, KeyObject>();
let jwksFetched = false;

async function fetchJwks(): Promise<void> {
  if (SUPABASE_URL === "") return;
  const url = `${SUPABASE_URL}/auth/v1/.well-known/jwks.json`;
  try {
    const res = await fetch(url);
    if (!res.ok) {
      console.warn("[SupabaseAuth] Failed to fetch JWKS (%d)", res.status);
      return;
    }
    const data = (await res.json()) as { keys?: JwkEntry[] };
    if (!data.keys || !Array.isArray(data.keys)) {
      console.warn("[SupabaseAuth] JWKS response has no keys array");
      return;
    }
    for (const jwk of data.keys) {
      if (jwk.kty !== "EC" || !jwk.kid) continue;
      try {
        const keyObj = createPublicKey({ key: jwk as unknown as import("node:crypto").JsonWebKey, format: "jwk" });
        jwksCache.set(jwk.kid, keyObj);
      } catch (err) {
        console.warn("[SupabaseAuth] Failed to import JWK kid=%s: %s", jwk.kid, err);
      }
    }
    console.log("[SupabaseAuth] Loaded %d EC public key(s) from JWKS", jwksCache.size);
  } catch (err) {
    console.warn("[SupabaseAuth] JWKS fetch error:", err);
  }
  jwksFetched = true;
}

// Fetch JWKS at module load (non-blocking)
fetchJwks();

// ---------------------------------------------------------------------------
// Minimal JWT decode
// ---------------------------------------------------------------------------

interface JwtPayload {
  sub?: string;
  email?: string;
  role?: string;
  aud?: string;
  exp?: number;
  iat?: number;
  [key: string]: unknown;
}

interface DecodedJwt {
  header: Record<string, unknown>;
  payload: JwtPayload;
  signatureInput: string;
  signatureRaw: Buffer;
  signatureB64url: string;
}

function base64UrlDecode(input: string): Buffer {
  let base64 = input.replace(/-/g, "+").replace(/_/g, "/");
  const pad = base64.length % 4;
  if (pad === 2) base64 += "==";
  else if (pad === 3) base64 += "=";
  return Buffer.from(base64, "base64");
}

function decodeJwt(token: string): DecodedJwt | null {
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  try {
    const header = JSON.parse(base64UrlDecode(parts[0]).toString("utf-8")) as Record<string, unknown>;
    const payload = JSON.parse(base64UrlDecode(parts[1]).toString("utf-8")) as JwtPayload;
    return {
      header,
      payload,
      signatureInput: `${parts[0]}.${parts[1]}`,
      signatureRaw: base64UrlDecode(parts[2]),
      signatureB64url: parts[2],
    };
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Verification
// ---------------------------------------------------------------------------

function verifyHS256(decoded: DecodedJwt): boolean {
  if (JWT_SECRET === "") return false;
  const expectedSig = createHmac("sha256", JWT_SECRET)
    .update(decoded.signatureInput)
    .digest("base64url");
  return expectedSig === decoded.signatureB64url;
}

function verifyES256(decoded: DecodedJwt): boolean {
  const kid = decoded.header.kid as string | undefined;
  if (!kid) {
    console.log("[SupabaseAuth] ES256 token has no kid");
    return false;
  }
  const pubKey = jwksCache.get(kid);
  if (!pubKey) {
    console.log("[SupabaseAuth] No public key found for kid=%s (have %d keys)", kid, jwksCache.size);
    return false;
  }

  // ES256 signature in JWTs is raw r||s (64 bytes), but Node's
  // crypto.createVerify expects DER-encoded. Convert.
  const sig = decoded.signatureRaw;
  if (sig.length !== 64) {
    console.log("[SupabaseAuth] ES256 signature unexpected length: %d", sig.length);
    return false;
  }
  const derSig = rawSigToDer(sig);

  const verifier = createVerify("SHA256");
  verifier.update(decoded.signatureInput);
  return verifier.verify(pubKey, derSig);
}

/**
 * Convert a raw ECDSA signature (r || s, 32 bytes each) to DER encoding.
 * Node's crypto.createVerify expects DER format for EC signatures.
 */
function rawSigToDer(raw: Buffer): Buffer {
  const r = raw.subarray(0, 32);
  const s = raw.subarray(32, 64);

  function encodeInteger(val: Buffer): Buffer {
    // Strip leading zeros, but ensure the high bit isn't set (add 0x00 padding if needed)
    let start = 0;
    while (start < val.length - 1 && val[start] === 0) start++;
    const trimmed = val.subarray(start);
    const needsPad = (trimmed[0] & 0x80) !== 0;
    const len = trimmed.length + (needsPad ? 1 : 0);
    const buf = Buffer.alloc(2 + len);
    buf[0] = 0x02; // INTEGER tag
    buf[1] = len;
    if (needsPad) {
      buf[2] = 0x00;
      trimmed.copy(buf, 3);
    } else {
      trimmed.copy(buf, 2);
    }
    return buf;
  }

  const rDer = encodeInteger(r);
  const sDer = encodeInteger(s);
  const seqLen = rDer.length + sDer.length;
  const seq = Buffer.alloc(2 + seqLen);
  seq[0] = 0x30; // SEQUENCE tag
  seq[1] = seqLen;
  rDer.copy(seq, 2);
  sDer.copy(seq, 2 + rDer.length);
  return seq;
}

/**
 * Verify a Supabase-issued JWT.
 * Returns the decoded payload on success, or null on failure.
 */
export function verifyToken(token: string): JwtPayload | null {
  const decoded = decodeJwt(token);
  if (decoded === null) return null;

  const alg = decoded.header.alg;

  let verified = false;
  if (alg === "HS256") {
    verified = verifyHS256(decoded);
    if (!verified && JWT_SECRET === "") {
      console.warn("[SupabaseAuth] SUPABASE_JWT_SECRET not set; skipping HS256 verification.");
      verified = true; // dev/LAN fallback
    }
  } else if (alg === "ES256") {
    verified = verifyES256(decoded);
  } else {
    console.log("[SupabaseAuth] Unsupported algorithm: %s", alg);
    return null;
  }

  if (!verified) {
    console.log("[SupabaseAuth] Signature verification failed (alg=%s)", alg);
    return null;
  }

  // Check expiry
  if (typeof decoded.payload.exp === "number" && decoded.payload.exp < Date.now() / 1000) {
    console.log("[SupabaseAuth] Token expired.");
    return null;
  }

  return decoded.payload;
}

/**
 * Extract the Supabase user ID (the `sub` claim) from a valid token.
 * Returns null if the token is invalid.
 */
export function getUserId(token: string): string | null {
  const payload = verifyToken(token);
  if (payload === null) return null;
  return typeof payload.sub === "string" ? payload.sub : null;
}
