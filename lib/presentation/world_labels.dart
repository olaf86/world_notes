import '../config/world_catalog.dart';
import '../l10n/app_localizations.dart';

String localizedWorldName(AppLocalizations l10n, WorldCatalogEntry world) {
  return switch (world.displayNameKey) {
    'world.asia' => l10n.worldAsia,
    'world.northAmerica' => l10n.worldNorthAmerica,
    'world.europe' => l10n.worldEurope,
    _ => world.worldId,
  };
}

String localizedWorldLocation(AppLocalizations l10n, WorldCatalogEntry world) {
  return switch (world.displayNameKey) {
    'world.asia' => l10n.worldAsiaLocation,
    'world.northAmerica' => l10n.worldNorthAmericaLocation,
    'world.europe' => l10n.worldEuropeLocation,
    _ => world.firestoreLocation,
  };
}
