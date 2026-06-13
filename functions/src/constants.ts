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

/** Coarse geohash precision stored on places for indexed map-pin queries. */
export const DISCOVERY_GEOHASH_PRECISION = 3;

/** Fine geohash precision used for map pin discovery. */
export const MAP_PIN_GEOHASH_PRECISION = 6;

/** Maximum map pins returned by one exploration request. */
export const MAP_PIN_RESULT_LIMIT = 120;

/** Radius from the user's current location that unlocks note details. */
export const NOTE_DETAIL_ACCESS_RADIUS_KM = 2;

/**
 * Region the functions are DEPLOYED to (matches the default DB in Tokyo).
 * The client picks which deployed region to call via Regions/effectiveRegion
 * in the app — keep the app's `available` regions in sync with where these
 * functions are actually deployed.
 */
export const REGION = "asia-northeast1";
