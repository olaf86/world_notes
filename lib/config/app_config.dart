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

  // Geohash precision for proximity queries (~1.2km radius)
  static const int geohashPrecision = 5;
  static const double searchRadiusKm = 2.0;

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

  static const String premiumEntitlementId = 'WorldNotes Premium';
  static const String premiumMonthlyProductId = 'monthly';
  static const String premiumYearlyProductId = 'yearly';
  static const String premiumLifetimeProductId = 'lifetime';

  // Message pagination
  static const int messagesPageSize = 20;
}
