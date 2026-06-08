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

/** Maximum delay before a scheduled note may be published. */
export const MAX_PUBLISH_DELAY_DAYS = 365;

/** Maximum delay before a scheduled message may be published. */
export const MAX_MESSAGE_PUBLISH_DELAY_DAYS = 7;

export const MAX_TITLE_LENGTH = 100;
export const MAX_SUBTITLE_LENGTH = 200;

/** Coarse geohash precision used for discovery grants. */
export const DISCOVERY_GEOHASH_PRECISION = 3;

/** Radius covered by a discovery grant, in kilometres. */
export const DISCOVERY_GRANT_RADIUS_KM = 100;

/** Discovery grant lifetime, in minutes. */
export const DISCOVERY_GRANT_TTL_MINUTES = 10;

/** Minimum interval between newly-issued grants for the same user. */
export const DISCOVERY_GRANT_MIN_INTERVAL_SECONDS = 30;

/** Rolling-ish fixed window used to cap grant creation. */
export const DISCOVERY_GRANT_WINDOW_MINUTES = 60;

/** Maximum newly-issued grants per window. */
export const DISCOVERY_GRANT_MAX_PER_WINDOW = 60;

/**
 * Region the functions are DEPLOYED to (matches the default DB in Tokyo).
 * The client picks which deployed region to call via Regions/effectiveRegion
 * in the app — keep the app's `available` regions in sync with where these
 * functions are actually deployed.
 */
export const REGION = "asia-northeast1";
