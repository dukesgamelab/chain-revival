/**
 * Server-side Supabase JWT verification.
 *
 * The JWT secret is loaded from the SUPABASE_JWT_SECRET environment variable.
 * You can find it in your Supabase dashboard under Settings > API > JWT Secret.
 *
 * Usage:
 *   SUPABASE_JWT_SECRET=your-jwt-secret npm run dev
 */

import { createHmac } from "node:crypto";

const JWT_SECRET = process.env.SUPABASE_JWT_SECRET ?? "";

// ---------------------------------------------------------------------------
// Minimal JWT decode + HMAC-SHA256 verification (no external dependency)
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

function base64UrlDecode(input: string): Buffer {
  // Base64url to standard base64
  let base64 = input.replace(/-/g, "+").replace(/_/g, "/");
  const pad = base64.length % 4;
  if (pad === 2) base64 += "==";
  else if (pad === 3) base64 += "=";
  return Buffer.from(base64, "base64");
}

function decodeJwt(token: string): { header: Record<string, unknown>; payload: JwtPayload; signatureInput: string; signature: string } | null {
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  try {
    const header = JSON.parse(base64UrlDecode(parts[0]).toString("utf-8")) as Record<string, unknown>;
    const payload = JSON.parse(base64UrlDecode(parts[1]).toString("utf-8")) as JwtPayload;
    return { header, payload, signatureInput: `${parts[0]}.${parts[1]}`, signature: parts[2] };
  } catch {
    return null;
  }
}

/**
 * Verify a Supabase-issued JWT.
 * Returns the decoded payload on success, or null on failure.
 */
export function verifyToken(token: string): JwtPayload | null {
  if (JWT_SECRET === "") {
    console.warn("[SupabaseAuth] SUPABASE_JWT_SECRET not set; skipping verification.");
    // In dev / LAN mode without the secret, decode but don't verify.
    const decoded = decodeJwt(token);
    return decoded?.payload ?? null;
  }

  const decoded = decodeJwt(token);
  if (decoded === null) return null;

  // Supabase uses HS256
  if (decoded.header.alg !== "HS256") return null;

  const expectedSig = createHmac("sha256", JWT_SECRET)
    .update(decoded.signatureInput)
    .digest("base64url");

  if (expectedSig !== decoded.signature) {
    console.log("[SupabaseAuth] Signature mismatch.");
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
