/**
 * Server-side mirror of the client's AppConfig constraints.
 * Keep these in sync with lib/config/app_config.dart.
 */
export const FREE_NOTE_LIMIT = 20;
export const PREMIUM_NOTE_LIMIT = 200;

/** Maximum messages per thread (must match AppConfig.maxMessagesPerThread). */
export const MAX_MESSAGES_PER_THREAD = 1000;

/** Write session lifetime, in minutes. */
export const WRITE_SESSION_TTL_MINUTES = 60;

/** Allowed note expiry presets, in days (must match noteExpiryPresetDays). */
export const NOTE_EXPIRY_PRESET_DAYS = [7, 30, 90, 180, 365];

export const MAX_TITLE_LENGTH = 100;
export const MAX_SUBTITLE_LENGTH = 200;

/**
 * Region the functions are DEPLOYED to (matches the default DB in Tokyo).
 * The client picks which deployed region to call via Regions/effectiveRegion
 * in the app — keep the app's `available` regions in sync with where these
 * functions are actually deployed.
 */
export const REGION = "asia-northeast1";
