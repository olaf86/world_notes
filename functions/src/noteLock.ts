import {defineSecret} from "firebase-functions/params";
import * as argon2 from "argon2";

// Server-only secret (pepper). Stored in Secret Manager, never in the repo.
// Set with: firebase functions:secrets:set NOTE_PW_PEPPER
export const NOTE_PW_PEPPER = defineSecret("NOTE_PW_PEPPER");

// argon2id parameters — OWASP minimum baseline.
const ARGON2_OPTS = {
  type: argon2.argon2id,
  memoryCost: 19456, // 19 MiB
  timeCost: 2,
  parallelism: 1,
} as const;

export const MAX_PATTERN_LENGTH = 30;
export const MAX_STRING_PASSWORD_LENGTH = 30;
export const MAX_LOCK_HINT_LENGTH = 140;
export type NoteLockType = "password" | "pattern";

/**
 * Server-side lock secret check (mirror of client-side validation).
 *
 * @param {string} pw The candidate password.
 * @param {NoteLockType} lockType The selected lock method.
 * @return {string | null} An error message, or null if the password is valid.
 */
export function validateLockSecret(
  pw: string,
  lockType: NoteLockType,
): string | null {
  if (lockType === "pattern") {
    return isValidPatternPassword(pw) ? null : "Invalid pattern.";
  }
  if (pw.length === 0) return "Enter a password.";
  if (pw.length > MAX_STRING_PASSWORD_LENGTH) {
    const max = MAX_STRING_PASSWORD_LENGTH;
    return `Password must be ${max} characters or fewer.`;
  }
  return null;
}

/**
 * Parses a client-visible lock type value.
 *
 * @param {unknown} value The raw Firestore or callable value.
 * @return {NoteLockType | null} The lock type, or null when absent/invalid.
 */
export function parseLockType(value: unknown): NoteLockType | null {
  return value === "password" || value === "pattern" ? value : null;
}

/**
 * Hashes a validated lock secret using the server pepper.
 *
 * @param {string} password The password or encoded pattern.
 * @return {Promise<string>} The argon2 hash.
 */
export async function hashLockSecret(password: string): Promise<string> {
  return argon2.hash(password, {
    ...ARGON2_OPTS,
    secret: Buffer.from(NOTE_PW_PEPPER.value()),
  });
}

/**
 * Verifies a lock secret candidate against a stored hash.
 *
 * @param {string} hash The stored argon2 hash.
 * @param {string} password The password or encoded pattern candidate.
 * @return {Promise<boolean>} Whether the candidate matches.
 */
export async function verifyLockSecret(
  hash: string,
  password: string,
): Promise<boolean> {
  return argon2.verify(hash, password, {
    secret: Buffer.from(NOTE_PW_PEPPER.value()),
  });
}

/**
 * Returns true when [pw] is an encoded 3x3 pattern lock path.
 *
 * @param {string} pw The encoded password candidate.
 * @return {boolean} Whether the candidate is a valid pattern lock.
 */
function isValidPatternPassword(pw: string): boolean {
  const patternPrefix = "pattern:v1:";
  if (!pw.startsWith(patternPrefix)) return false;
  const encoded = pw.slice(patternPrefix.length);
  if (!new RegExp(`^[0-8]{1,${MAX_PATTERN_LENGTH}}$`).test(encoded)) {
    return false;
  }
  for (let i = 1; i < encoded.length; i++) {
    if (!areAdjacentPatternNodes(encoded[i - 1], encoded[i])) return false;
  }
  return true;
}

/**
 * Checks that two 3x3 pattern lock nodes are neighboring dots.
 *
 * @param {string} a The previous node id, encoded as 0-8.
 * @param {string} b The next node id, encoded as 0-8.
 * @return {boolean} Whether the nodes can be connected directly.
 */
function areAdjacentPatternNodes(a: string, b: string): boolean {
  if (a === b) return false;
  const from = Number(a);
  const to = Number(b);
  const ax = from % 3;
  const ay = Math.floor(from / 3);
  const bx = to % 3;
  const by = Math.floor(to / 3);
  return Math.abs(ax - bx) <= 1 && Math.abs(ay - by) <= 1;
}
