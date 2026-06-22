class AppConfig {
  static const stadiaApiKey = String.fromEnvironment(
    'STADIA_API_KEY',
    defaultValue: '',
  );

  // MapLibre style using Stadia Maps (free tier)
  static const mapStyleUrl =
      'https://tiles.stadiamaps.com/styles/alidade_smooth.json';

  static String mapStyleUrlWithKey(String apiKey) {
    if (apiKey.isEmpty) return mapStyleUrl;
    return '$mapStyleUrl?api_key=$apiKey';
  }

  static const double defaultLatitude = 35.6812;
  static const double defaultLongitude = 139.7671;
  static const double defaultZoom = 14.0;

  // Ads
  static const String bannerAdUnitId = String.fromEnvironment(
    'BANNER_AD_UNIT_ID',
    defaultValue: 'ca-app-pub-3940256099942544/6300978111', // test ID
  );

  // RevenueCat
  static const String revenueCatApiKeyIos = String.fromEnvironment(
    'REVENUECAT_API_KEY_IOS',
    defaultValue: '',
  );
  static const String revenueCatApiKeyAndroid = String.fromEnvironment(
    'REVENUECAT_API_KEY_ANDROID',
    defaultValue: '',
  );

  static const String proPlanName = 'World Notes PRO';
  static const String proEntitlementId = 'pro';
  static const String proMonthlyProductId = 'world_notes_pro_monthly';
  static const String proYearlyProductId = 'world_notes_pro_yearly';
  static const String proMonthlyPriceLabel = '¥300';
  static const String proYearlyPriceLabel = '¥2,980';
  static const String proYearlyLaunchPriceLabel = '¥1,980';
  static const String proMonthlyUsdPriceLabel = '\$2';
  static const String proYearlyUsdPriceLabel = '\$20';

  // Message pagination
  static const int messagesPageSize = 20;

  // ── Application constraints ───────────────────────────────────────────────

  /// Maximum number of messages allowed per note thread.
  /// Firestore rules enforce this server-side.
  static const int maxMessagesPerThread = 1000;

  /// Maximum notes a user can register for nearby message alerts.
  /// Must match NEARBY_NOTIFICATION_LIMIT in functions/src/constants.ts.
  static const int nearbyNotificationLimit = 5;

  /// Maximum distance from a note at which its detail can be opened.
  /// Must match NOTE_DETAIL_ACCESS_RADIUS_KM in functions/src/constants.ts.
  static const int noteDetailAccessRadiusMeters = 500;

  /// Nearby alerts use the same radius as note detail read/post access.
  static const int nearbyNotificationRadiusMeters =
      noteDetailAccessRadiusMeters;

  /// Minimum interval between active in-range unread checks for a followed
  /// nearby note while the app is running.
  static const int nearbyNotificationCheckCooldownMinutes = 10;

  /// Maximum character length of a single message.
  static const int maxMessageLength = 2000;

  /// Maximum delay before a scheduled message may be published.
  static const int maxMessagePublishDelayDays = 7;

  /// Maximum active notes a free user may own simultaneously.
  static const int freeNoteLimit = 20;

  /// Maximum active notes a PRO user may own simultaneously.
  static const int proNoteLimit = 200;

  /// Maximum image size (bytes) accepted for upload.
  static const int maxImageBytes = 5 * 1024 * 1024; // 5 MB

  /// Maximum lifetime of a note before it auto-archives.
  static const int maxNoteLifetimeDays = 365;

  /// Expiry presets (in days) offered when creating a note. Selection is
  /// required — a note can never be created without an expiry.
  static const List<int> noteExpiryPresetDays = [7, 30, 90, 180, 365];

  /// Default expiry preset pre-selected on the note creation screen (3 months).
  /// Must be one of [noteExpiryPresetDays].
  static const int defaultNoteExpiryDays = 90;

  /// Base URL for private-note invite links. The path is `/i/{token}` and is
  /// handled as a deep link (Universal Links / App Links) once the associated
  /// domain is configured. Host: worldnotes.asobo.dev (Firebase Hosting).
  static const String inviteLinkBase = 'https://worldnotes.asobo.dev/i/';

  /// Builds the shareable invite URL for a token.
  static String inviteLink(String token) => '$inviteLinkBase$token';
}
