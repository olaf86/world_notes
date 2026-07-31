import {ASIA_WORLD} from "./platform/worldRegistry";

/**
 * Server-side mirror of the client's AppConfig constraints.
 * Keep these in sync with lib/config/app_config.dart.
 */
export const FREE_NOTE_LIMIT = 20;
export const PREMIUM_NOTE_LIMIT = 200;

/** Maximum messages per thread (must match AppConfig.maxMessagesPerThread). */
export const MAX_MESSAGES_PER_THREAD = 1000;

/** Maximum images per message (must match AppConfig.maxMessageImages). */
export const MAX_MESSAGE_IMAGES = 4;

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

/** Coarse geohash precision retained for broad discovery compatibility. */
export const DISCOVERY_GEOHASH_PRECISION = 3;

/** Mid-area geohash precision used before falling back to wide-area cells. */
export const MAP_PIN_MID_GEOHASH_PRECISION = 5;

/** Fine geohash precision used for map pin discovery. */
export const MAP_PIN_GEOHASH_PRECISION = 6;

/** Maximum map pins returned by one exploration request. */
export const MAP_PIN_RESULT_LIMIT = 120;

/** Maximum map pins returned when the map is zoomed out to coarse discovery. */
export const MAP_PIN_ZOOMED_OUT_RESULT_LIMIT = 60;

/** Maximum server-accepted search radius for one map-pin request. */
export const MAP_PIN_MAX_SEARCH_RADIUS_KM = 20;

/** At or below this radius, use precision-6 cells for fine map pin search. */
export const MAP_PIN_FINE_SEARCH_MAX_RADIUS_KM = 4;

/** Above this radius, use the wider precision-4 map pin geohash field. */
export const MAP_PIN_MID_SEARCH_MAX_RADIUS_KM = 12;

/** Radius from the user's current location that unlocks note details. */
export const NOTE_DETAIL_ACCESS_RADIUS_KM = 0.5;

/** PRO radius from the user's current location that unlocks note details. */
export const PRO_NOTE_DETAIL_ACCESS_RADIUS_KM = 1.0;

/**
 * Region of the Asia deployment, derived from the trusted world catalog.
 */
export const REGION = ASIA_WORLD.functionsRegion;
