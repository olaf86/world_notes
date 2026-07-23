// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'World Notes';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonSave => 'Save';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonTryAgain => 'Try again';

  @override
  String commonError(Object error) {
    return 'Error: $error';
  }

  @override
  String get navMap => 'Map';

  @override
  String get navNotes => 'Notes';

  @override
  String get navNotifications => 'Notifications';

  @override
  String get navProfile => 'Profile';

  @override
  String get locationPermissionTitle => 'Location Required';

  @override
  String get locationPermissionMessage =>
      'Enable location tracking to enjoy World Notes.';

  @override
  String get locationPermissionOpenSettings => 'Open Settings';

  @override
  String get locationPermissionAllow => 'Allow Location';

  @override
  String get locationServiceDisabledTitle => 'Turn On Location Services';

  @override
  String get locationServiceDisabledMessage =>
      'Turn on location services to use World Notes.';

  @override
  String get locationServiceOpenSettings => 'Open Location Settings';

  @override
  String get locationSearching => 'Finding your location…';

  @override
  String get locationUnavailable => 'Location unavailable.';

  @override
  String get locationUnavailableHelp =>
      'Allow location access in Settings,\nor move to an area with better GPS signal.';

  @override
  String get locationLoadFailed => 'Failed to load location.';

  @override
  String get currentLocationUnavailable =>
      'Could not get your current location.';

  @override
  String get enableLocation => 'Enable Location';

  @override
  String get enableLocationSettingsTooltip =>
      'Open settings to enable location';

  @override
  String get enableLocationPermissionTooltip => 'Allow location to add notes';

  @override
  String get enableLocationServiceTooltip => 'Open location settings';

  @override
  String get mapNotesTitle => 'Map Notes';

  @override
  String get mapAddNote => 'Add Note';

  @override
  String get mapList => 'List';

  @override
  String get mapRefreshNotes => 'Refresh map notes';

  @override
  String mapHideAccessArea(String radius) {
    return 'Hide $radius access area';
  }

  @override
  String mapShowAccessArea(String radius) {
    return 'Show $radius access area';
  }

  @override
  String get mapLoadingNotes => 'Loading map notes…';

  @override
  String get mapNoNotes =>
      'No notes in this area.\nMove the map or drop one here!';

  @override
  String mapDistanceMeters(int distance) {
    return '$distance meters away';
  }

  @override
  String mapDistanceKilometers(String distance) {
    return '$distance km away';
  }

  @override
  String get mapFromFollowing => 'From someone you follow';

  @override
  String get mapNewFromFollowing => 'New from someone you follow';

  @override
  String get mapFromFollowingSemantic => 'From a followed author.';

  @override
  String get newMessages => 'New messages';

  @override
  String createdAt(String date) {
    return 'Created at $date';
  }

  @override
  String expiresAt(String date) {
    return 'Expires $date';
  }

  @override
  String get noteClosed => 'Closed';

  @override
  String get notePrivate => 'Private';

  @override
  String get noteWithinRange => 'Within access range. You can open this note.';

  @override
  String get noteOutsideRange =>
      'Outside access range. Move closer to open this note.';

  @override
  String get noteOpenNow => 'Open now';

  @override
  String get noteMoveCloser => 'Move closer to open';

  @override
  String messageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messages',
      one: '1 message',
    );
    return '$_temp0';
  }

  @override
  String likeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count likes',
      one: '1 like',
    );
    return '$_temp0';
  }

  @override
  String footprintCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count footprints',
      one: '1 footprint',
    );
    return '$_temp0';
  }

  @override
  String get footprintsOn => 'Footprints on';

  @override
  String get footprintsOff => 'Footprints off';

  @override
  String get noteOpening => 'Opening…';

  @override
  String get noteView => 'View Note';

  @override
  String get noteOpen => 'Open Note';

  @override
  String get noteAvailableNearby => 'Available nearby';

  @override
  String get noteExpired => 'Expired';

  @override
  String noteExpiresMonths(int count) {
    return 'Expires in $count months';
  }

  @override
  String noteExpiresDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Expires in $count days',
      one: 'Expires in 1 day',
    );
    return '$_temp0';
  }

  @override
  String noteExpiresHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Expires in $count hours',
      one: 'Expires in 1 hour',
    );
    return '$_temp0';
  }

  @override
  String get noteExpiresSoon => 'Expires soon';

  @override
  String get goPro => 'Go PRO';

  @override
  String get threadOptions => 'Thread options';

  @override
  String get writeMessage => 'Write a message';

  @override
  String get likeNote => 'Like note';

  @override
  String get unlikeNote => 'Unlike note';

  @override
  String get cannotLikeOwnNote => 'You cannot like your own note';

  @override
  String get likeUnavailable => 'Like unavailable';

  @override
  String get noMessages => 'No messages yet.\nBe the first to write!';

  @override
  String get noNotifications => 'No notifications yet.';

  @override
  String get noFollowers => 'No followers yet.';

  @override
  String get noFollowing => 'Not following anyone yet.';

  @override
  String get noFootprints => 'No footprints yet.';

  @override
  String get noFootprintsDescription =>
      'Visitors will appear here after they open this note.';

  @override
  String get noAccessMembers =>
      'No one has access yet. Share the link to add people.';

  @override
  String get noModerationReviews => 'No reviews.';

  @override
  String get youLabel => 'You';

  @override
  String get messageSending => 'Sending…';

  @override
  String messageScheduledAt(String time) {
    return 'Scheduled $time';
  }

  @override
  String get noteCreateTitle => 'New Note';

  @override
  String get noteTitleLabel => 'Title';

  @override
  String get noteTitleHint => 'What is this place?';

  @override
  String get noteTitleRequired => 'Title is required';

  @override
  String get noteDescriptionOptionalLabel => 'Description (optional)';

  @override
  String get noteDescriptionHint => 'Tell us about this place…';

  @override
  String get noteThemeLabel => 'Note theme';

  @override
  String get noteThemeChangeTitle => 'Change theme';

  @override
  String get noteThemeChangeDescription =>
      'This changes the note appearance for everyone.';

  @override
  String get pinColorLabel => 'Pin color';

  @override
  String get pinStyleLabel => 'Pin style';

  @override
  String get pinImageLabel => 'Pin image';

  @override
  String get iconLabel => 'Icon';

  @override
  String get imageLabel => 'Image';

  @override
  String get publishLabel => 'Publish';

  @override
  String get publishNow => 'Now';

  @override
  String get publishLater => 'Later';

  @override
  String get publishLaterSchedule => 'Publish later';

  @override
  String get publishIn15Minutes => '15 minutes';

  @override
  String get publishIn30Minutes => '30 minutes';

  @override
  String get publishIn1Hour => '1 hour';

  @override
  String get publishIn3Hours => '3 hours';

  @override
  String get publishTomorrow => 'Tomorrow';

  @override
  String get publishCustom => 'Custom';

  @override
  String get autoCloseAfter => 'Auto-close after';

  @override
  String get autoCloseDescription =>
      'Stops accepting messages and archives the note after this period.';

  @override
  String get expiryOneWeek => '1 week';

  @override
  String get expiryOneMonth => '1 month';

  @override
  String expiryMonths(int count) {
    return '$count months';
  }

  @override
  String get expiryOneYear => '1 year';

  @override
  String expiryDays(int count) {
    return '$count days';
  }

  @override
  String get noteAccessLabel => 'Access';

  @override
  String get createNoteAction => 'Create Note';

  @override
  String get noteCapacityChecking => 'Checking available note slots…';

  @override
  String get noteLimitReached => 'Note limit reached';

  @override
  String premiumNoteLimitMessage(int count, int limit) {
    return 'You have $count of $limit active notes. Archive one or wait for one to expire before creating another.';
  }

  @override
  String freeNoteLimitMessage(int limit, int proLimit) {
    return 'Free accounts can keep $limit active notes. Archive one or upgrade to PRO for up to $proLimit.';
  }

  @override
  String get forkLocationNotice =>
      'This new note will use the archived note\'s location.';

  @override
  String get noteCreateLocationPermissionRequired =>
      'Location permission is required to create a note.';

  @override
  String get noteCreateLocationPermissionDisabledMessage =>
      'Location permission is disabled. Open system settings and allow location access to create notes.';

  @override
  String get noteCreateLocationServiceDisabledMessage =>
      'Location services are turned off. Turn them on to create a note at your current location.';

  @override
  String get noteCreateLocationUnavailable =>
      'Could not get your current location. Please try again.';

  @override
  String get imagePin => 'Image pin';

  @override
  String get imagePinReady => 'Image pin ready';

  @override
  String get pinImageEmptyDescription =>
      'Add a cropped thumbnail. The default pin is used as fallback.';

  @override
  String get pinImageReadyDescription =>
      'This cropped thumbnail will be uploaded.';

  @override
  String get chooseImage => 'Choose image';

  @override
  String get changeImage => 'Change image';

  @override
  String get removeImage => 'Remove image';

  @override
  String get passwordLabel => 'Password';

  @override
  String get patternLabel => 'Pattern';

  @override
  String get publicNote => 'Public note';

  @override
  String get lockedNote => 'Locked note';

  @override
  String noteLockSummary(String type) {
    return '$type lock';
  }

  @override
  String noteLockSummaryWithHint(String type) {
    return '$type lock with hint';
  }

  @override
  String get anyoneNearbyCanOpen => 'Anyone nearby can open it.';

  @override
  String get setLock => 'Set lock';

  @override
  String get changeLock => 'Change lock';

  @override
  String get removeLock => 'Remove lock';

  @override
  String get noteThemeStandard => 'Standard';

  @override
  String get noteThemeStandardDescription =>
      'The calm, familiar World Notes appearance.';

  @override
  String get noteThemeAurora => 'Aurora';

  @override
  String get noteThemeAuroraDescription => 'Indigo with aqua and violet light.';

  @override
  String get noteThemeCitrus => 'Citrus Pop';

  @override
  String get noteThemeCitrusDescription =>
      'Warm coral, orange, and a teal lift.';

  @override
  String get noteThemeBotanical => 'Botanical';

  @override
  String get noteThemeBotanicalDescription => 'Grounded jade and leaf green.';

  @override
  String get noteThemeNeon => 'Neon Grid';

  @override
  String get noteThemeNeonDescription => 'Cyber cyan and fuchsia after dark.';

  @override
  String get noteThemeEditorial => 'Editorial';

  @override
  String get noteThemeEditorialDescription =>
      'Paper neutrals with a cobalt signal.';

  @override
  String get noteFallbackTitle => 'Note';

  @override
  String get noteUnavailableTitle => 'This note is not available.';

  @override
  String get noteUnavailableMessage =>
      'It may not be published yet, may have expired, or may no longer be accessible from here.';

  @override
  String get noteOpenFailedTitle => 'Could not open this note.';

  @override
  String get noteOpenFailedMessage =>
      'Check your connection and make sure you are still nearby.';

  @override
  String get noteReadOnlyFromMyNotes => 'Read-only from My Notes.';

  @override
  String get notePrivateTitle => 'This note is private';

  @override
  String get notePrivatePasswordDescription =>
      'Enter the password to read and post messages.';

  @override
  String get notePrivatePatternDescription =>
      'Draw the pattern to read and post messages.';

  @override
  String get notePrivateDescription =>
      'Unlock this note to read and post messages.';

  @override
  String get enterPassword => 'Enter password';

  @override
  String get drawPattern => 'Draw pattern';

  @override
  String get unlockAction => 'Unlock';

  @override
  String noteLockHint(String hint) {
    return 'Hint: $hint';
  }

  @override
  String get noteScheduledReadOnly =>
      'This note is scheduled and is not accepting messages yet.';

  @override
  String get noteArchivedReadOnly =>
      'This note has been archived. It is read-only.';

  @override
  String threadMessageLimitReached(int count) {
    return 'This thread reached its $count-message limit and is now closed.';
  }

  @override
  String get threadFullClosed => 'This thread is full and closed.';

  @override
  String get threadMaintainerClosed =>
      'A maintainer closed this thread. It is read-only.';

  @override
  String get closeThreadAction => 'Close thread';

  @override
  String get reopenThreadAction => 'Re-open thread';

  @override
  String get changeThemeAction => 'Change theme';

  @override
  String get manageAccessAction => 'Manage access';

  @override
  String sortNotesTooltip(String sort) {
    return 'Sort notes: $sort';
  }

  @override
  String sortNotesSelected(String sort) {
    return 'Sort notes. $sort selected';
  }

  @override
  String sortedBy(String sort) {
    return 'Sorted by: $sort';
  }

  @override
  String get sortDistance => 'Distance';

  @override
  String get sortLastActivity => 'Last activity';

  @override
  String get sortNewest => 'Newest';

  @override
  String get sortExpiresSoon => 'Expires soon';

  @override
  String get sortMostLiked => 'Most liked';

  @override
  String get sortArchivedNewest => 'Recently archived';

  @override
  String get sortArchivedOldest => 'Oldest archived';

  @override
  String get myNotesTitle => 'Notes';

  @override
  String get myNotesTab => 'My Notes';

  @override
  String get archivedNotesTab => 'Archived';

  @override
  String get archiveNoteTitle => 'Archive this note?';

  @override
  String get archiveNoteMessage =>
      'It will disappear from the map, become read-only, and free one note slot. You cannot restore the archived note, but you can create a new note from its title, description, and location later.';

  @override
  String get archiveAction => 'Archive';

  @override
  String archiveFailed(Object error) {
    return 'Failed to archive note: $error';
  }

  @override
  String get loadMore => 'Load more';

  @override
  String get retryLoadMore => 'Retry loading more';

  @override
  String get createdNotes => 'Created notes';

  @override
  String get archivedNotes => 'Archived notes';

  @override
  String lastActive(String time) {
    return 'Last active $time';
  }

  @override
  String archivedAt(String time) {
    return 'Archived $time';
  }

  @override
  String get createFromArchiveTooltip => 'Create new note from archive';

  @override
  String get archiveNoteTooltip => 'Archive note';

  @override
  String relativeDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days ago',
      one: '1 day ago',
    );
    return '$_temp0';
  }

  @override
  String relativeHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours ago',
      one: '1 hour ago',
    );
    return '$_temp0';
  }

  @override
  String relativeMinutesAgo(int count) {
    return '$count min ago';
  }

  @override
  String get relativeJustNow => 'just now';

  @override
  String get noArchivedNotes => 'No archived notes yet.';

  @override
  String get noMyNotes => 'No notes yet.\nCreate one from the Map tab.';

  @override
  String get profileTitle => 'Profile';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsLanguageTitle => 'App Language';

  @override
  String get settingsLanguageSystem => 'Automatic (System)';

  @override
  String get settingsLanguageSystemDescription => 'Use your device language';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguageJapanese => '日本語';

  @override
  String get settingsLanguageKorean => '한국어';

  @override
  String get settingsLanguageSimplifiedChinese => '简体中文';

  @override
  String get settingsLanguageTraditionalChinese => '繁體中文';

  @override
  String get settingsLanguageUpdateFailed =>
      'The language changed on this device, but could not be saved to your account.';

  @override
  String get settingsMapStyleTitle => 'Map Style';

  @override
  String get settingsMapStyleAuto => 'Auto';

  @override
  String get settingsMapStyleStandard => 'Standard';

  @override
  String get settingsMapStyleLight => 'Light';

  @override
  String get settingsMapStyleDark => 'Dark';

  @override
  String get settingsMapStylePop => 'Pop';

  @override
  String get settingsMapStyleAutoDescription => 'Follow the system appearance';

  @override
  String get settingsMapStyleStandardDescription => 'Clean & minimal';

  @override
  String get settingsMapStyleLightDescription => 'Use Apple Maps in light mode';

  @override
  String get settingsMapStyleDarkDescription => 'Easy on the eyes at night';

  @override
  String get settingsMapStylePopDescription => 'Bright & colourful';

  @override
  String get settingsDataRegionTitle => 'Data Region';

  @override
  String get settingsDataRegionDescription =>
      'Choose which region serves your requests. Auto picks the closest to your current location — handy to override while travelling.';

  @override
  String get settingsDataRegionAuto => 'Auto (nearest)';

  @override
  String settingsDataRegionCurrent(String region) {
    return 'Currently: $region';
  }

  @override
  String get settingsRegionAsiaTokyo => 'Asia (Tokyo)';

  @override
  String get settingsRegionAmericasUsCentral => 'Americas (US Central)';

  @override
  String get settingsRegionEuropeBelgium => 'Europe (Belgium)';

  @override
  String get settingsNotificationsTitle => 'Notifications';

  @override
  String get notificationsMaintainedNotesTitle => 'Maintained notes';

  @override
  String get notificationsMaintainedNotesDescription =>
      'Receive notifications when notes you maintain get new messages.';

  @override
  String get notificationsTurnOnTooltip =>
      'Turn on maintained-note notifications';

  @override
  String get notificationsTurnOffTooltip =>
      'Turn off maintained-note notifications';

  @override
  String get notificationsPermissionDenied =>
      'Notifications are not allowed. Enable notifications in system settings to receive new message alerts.';

  @override
  String get notificationsEnableFailed =>
      'Could not enable maintained-note notifications.';

  @override
  String get notificationsDisableFailed =>
      'Could not disable maintained-note notifications.';

  @override
  String get notificationPreviewsTitle => 'Message previews';

  @override
  String get notificationPreviewsDescription =>
      'Show message text in maintained-note alerts.';

  @override
  String get notificationPreviewsUpdateFailed =>
      'Could not update notification previews.';

  @override
  String get editNickname => 'Edit nickname';

  @override
  String get nicknameLabel => 'Nickname';

  @override
  String get nicknameUpdated => 'Nickname updated.';

  @override
  String nicknameUpdateFailed(Object error) {
    return 'Failed to update nickname: $error';
  }

  @override
  String get manageSubscription => 'Manage Subscription';

  @override
  String get upgradeToPro => 'Upgrade to PRO';

  @override
  String get proBenefitsSummary =>
      'Remove ads, keep 200 notes, and unlock PRO features';

  @override
  String get subscriptionManagementSummary => 'Billing, cancellation & support';

  @override
  String get proHeroTitle => 'Make every place memorable';

  @override
  String get proHeroSubtitle =>
      'Unlock more ways to leave, revisit, and share notes around the world.';

  @override
  String get proFeatureAdFree => 'Enjoy World Notes without ads';

  @override
  String proFeatureNoteLimit(int count) {
    return 'Keep up to $count active notes';
  }

  @override
  String get proFeatureAccessArea => 'Open nearby notes from a wider area';

  @override
  String proMonthlyPlan(String price) {
    return '$price / month';
  }

  @override
  String proYearlyPlan(String price) {
    return '$price / year';
  }

  @override
  String proIntroOffer(String price) {
    return 'First year $price';
  }

  @override
  String get proChoosePlan => 'Choose your PRO plan';

  @override
  String get moderation => 'Moderation';

  @override
  String get signOut => 'Sign Out';

  @override
  String get followers => 'Followers';

  @override
  String get following => 'Following';

  @override
  String subscriptionUnavailableBuild(String planName) {
    return '$planName is not available in this build.';
  }

  @override
  String subscriptionTemporarilyUnavailable(String planName) {
    return '$planName is temporarily unavailable.';
  }
}
