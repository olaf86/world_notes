/**
 * Server-side mirror of the client's AppConfig constraints.
 * Keep these in sync with lib/config/app_config.dart.
 */
export const FREE_NOTE_LIMIT = 3;
export const PREMIUM_NOTE_LIMIT = 10;

/** Allowed note expiry presets, in days (must match noteExpiryPresetDays). */
export const NOTE_EXPIRY_PRESET_DAYS = [7, 30, 90, 180, 365];

export const MAX_TITLE_LENGTH = 100;
export const MAX_SUBTITLE_LENGTH = 200;

/** Firestore / Functions region (matches the default DB in Tokyo). */
export const REGION = "asia-northeast1";
