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
  String get reportMessageAction => 'Report message';

  @override
  String get reportNoteAction => 'Report note';

  @override
  String get reportMessageTitle => 'Report message';

  @override
  String get reportNoteTitle => 'Report note';

  @override
  String get reportMessageQuestion => 'Why are you reporting this message?';

  @override
  String get reportNoteQuestion => 'Why are you reporting this note?';

  @override
  String get reportReasonSpam => 'Spam or advertising';

  @override
  String get reportReasonHarassment => 'Harassment or bullying';

  @override
  String get reportReasonSexual => 'Adult or explicit content';

  @override
  String get reportReasonIllegal => 'Illegal content';

  @override
  String get reportReasonOther => 'Other';

  @override
  String get reportMessagePrivacy =>
      'Your user ID, this message ID, the note ID, and the selected reason will be shared with administrators for review.';

  @override
  String get reportNotePrivacy =>
      'Your user ID, this note ID, and the selected reason will be shared with administrators for review.';

  @override
  String get reportSubmitting => 'Submitting...';

  @override
  String get reportSubmitAction => 'Submit report';

  @override
  String get reportSubmitted =>
      'Report submitted. Thank you for helping keep this community safe.';

  @override
  String get reportAlsoBlockUser => 'Also block this user';

  @override
  String get reportAlsoBlockUserDescription =>
      'Their notes and messages will be hidden after this report is submitted.';

  @override
  String get reportSubmittedBlockFailed =>
      'The report was submitted, but the user could not be blocked.';

  @override
  String reportFailed(Object error) {
    return 'Failed to submit report: $error';
  }

  @override
  String get reportCooldown =>
      'Please wait a moment before submitting another report.';

  @override
  String get reportUnavailable => 'This content can no longer be reported.';

  @override
  String get contentModerationUnavailable =>
      'The safety check is temporarily unavailable. Please try again.';

  @override
  String get contentNotAllowed =>
      'This content cannot be published. Please revise it and try again.';

  @override
  String get imageNotAllowed =>
      'This image cannot be used. Please choose another image.';

  @override
  String get noteCreatedPinImageUploadFailed =>
      'The note was created, but its pin image could not be uploaded.';

  @override
  String get noteCreateNetworkError =>
      'Could not reach the server. Check your internet connection and try again.';

  @override
  String get noteCreateAuthenticationRequired =>
      'Please sign in again to create a note.';

  @override
  String get noteCreateFailed => 'Could not create the note. Please try again.';

  @override
  String get noteCreateUnexpectedError =>
      'An unexpected error occurred. Please try again.';

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
  String get useLock => 'Use lock';

  @override
  String get updateAction => 'Update';

  @override
  String get confirmPasswordLabel => 'Confirm password';

  @override
  String get patternSetupInstruction => 'Draw a path between neighboring dots.';

  @override
  String get lockHintOptional => 'Hint (optional)';

  @override
  String get clearAction => 'Clear';

  @override
  String get passwordRequired => 'Enter a password.';

  @override
  String passwordMaxLength(int maxLength) {
    return 'Password must be $maxLength characters or fewer.';
  }

  @override
  String get passwordConfirmationRequired => 'Re-enter the password.';

  @override
  String get passwordsDoNotMatch => 'Passwords do not match.';

  @override
  String get patternRequired => 'Draw a pattern to lock this note.';

  @override
  String patternTooLong(int maxLength) {
    return 'Pattern is too long. Use $maxLength nodes or fewer.';
  }

  @override
  String get patternInvalidNode => 'Pattern contains an invalid node.';

  @override
  String get patternNeighboringOnly =>
      'Pattern can only connect neighboring dots.';

  @override
  String get lockSavedPrivate => 'Lock saved. This note is private.';

  @override
  String get lockSaveFailed => 'Failed to save the lock.';

  @override
  String get appVerificationFailed =>
      'Could not verify this app. Please try again.';

  @override
  String get authenticationExpired =>
      'Authentication failed. Please sign in again.';

  @override
  String get lockCreatorOnly => 'Only the note creator can change this lock.';

  @override
  String get noteNotFound => 'Note not found.';

  @override
  String get incorrectPattern => 'Incorrect pattern.';

  @override
  String get incorrectPassword => 'Incorrect password.';

  @override
  String get tooManyAttempts => 'Too many attempts. Please try again later.';

  @override
  String get noteUnlockFailed => 'Could not unlock this note.';

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
  String get blockUserAction => 'Block user';

  @override
  String get unblockUserAction => 'Unblock user';

  @override
  String blockUserTitle(String name) {
    return 'Block $name?';
  }

  @override
  String get blockUserConfirmation =>
      'Their notes and messages will be hidden. You will unfollow each other, and they will lose access to notes you own. You may still encounter each other in notes owned by someone else.';

  @override
  String get blockUserConfirmAction => 'Block';

  @override
  String unblockUserTitle(String name) {
    return 'Unblock $name?';
  }

  @override
  String get unblockUserConfirmation =>
      'Their content may appear again. Previous follows and access to your notes will not be restored.';

  @override
  String userBlocked(String name) {
    return '$name has been blocked.';
  }

  @override
  String userUnblocked(String name) {
    return '$name has been unblocked.';
  }

  @override
  String updateUserBlockFailed(Object error) {
    return 'Could not update the block setting: $error';
  }

  @override
  String get settingsTitle => 'Settings';

  @override
  String get blockedUsersTitle => 'Blocked users';

  @override
  String get blockedUsersDescription =>
      'Review or unblock people you have blocked';

  @override
  String get noBlockedUsers => 'You have not blocked anyone.';

  @override
  String blockedUsersLoadFailed(Object error) {
    return 'Could not load blocked users: $error';
  }

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
  String get settingsContentWorldTitle => 'Content world';

  @override
  String get settingsContentWorldDescription =>
      'Choose where you browse and post. Your permanent home world will not change.';

  @override
  String get settingsContentWorldSwitchFailed =>
      'Could not switch worlds. Please try again.';

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
  String get homeWorldSelectionTitle => 'Choose your home world';

  @override
  String get homeWorldSelectionIntro =>
      'Your home world keeps your account data close to you.';

  @override
  String get homeWorldSelectionPermanentWarning =>
      'This choice cannot be changed later. You can still visit other prepared worlds without moving your home.';

  @override
  String get homeWorldSelectionUnavailable =>
      'No home world is currently available.';

  @override
  String get homeWorldSelectionLoadFailed =>
      'Could not load your account setup.';

  @override
  String get homeWorldSelectionSubmitFailed =>
      'Could not set your home world. Please try again.';

  @override
  String get homeWorldSelectionConfirm => 'Set as my permanent home';

  @override
  String get worldAsia => 'Asia';

  @override
  String get worldAsiaLocation => 'Tokyo, Japan';

  @override
  String get worldNorthAmerica => 'North America';

  @override
  String get worldNorthAmericaLocation => 'Iowa, United States';

  @override
  String get worldEurope => 'Europe';

  @override
  String get worldEuropeLocation => 'Belgium';

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

  @override
  String get adminAccountSafety => 'Account safety';

  @override
  String get adminSafetyTargetUid => 'Target user ID';

  @override
  String get adminSafetyLoad => 'Load account safety';

  @override
  String get adminSafetyPoints => 'Violation points';

  @override
  String get adminSafetyAuthorityWorld => 'Authority world';

  @override
  String get adminSafetyRestriction => 'Posting restriction';

  @override
  String get adminSafetyBan => 'Ban';

  @override
  String get adminSafetyNone => 'None';

  @override
  String get adminSafetyPermanent => 'Permanent';

  @override
  String get adminSafetyAdjustPoints => 'Adjust points';

  @override
  String get adminSafetyPointDelta => 'Point change';

  @override
  String get adminSafetyPointDeltaHelp =>
      'Enter an integer from -100 to 100, excluding 0.';

  @override
  String adminSafetySetRestriction(int days) {
    return 'Restrict for $days day(s)';
  }

  @override
  String get adminSafetyClearRestriction => 'Clear restriction';

  @override
  String adminSafetySetBan(int days) {
    return 'Ban for $days days';
  }

  @override
  String get adminSafetySetPermanentBan => 'Set permanent ban';

  @override
  String get adminSafetyClearBan => 'Clear ban';

  @override
  String get adminSafetyReason => 'Reason (required)';

  @override
  String get adminSafetyReference => 'Review or support reference (optional)';

  @override
  String get adminSafetyApply => 'Apply';

  @override
  String get adminSafetyContinue => 'Continue';

  @override
  String get adminSafetyAccepted =>
      'The operation was accepted and will continue in the background.';

  @override
  String get adminSafetyAuditHistory => 'Administrator history';

  @override
  String get adminSafetyNoAudits => 'No administrator actions.';

  @override
  String get administratorInvitationTitle => 'Administrator invitation';

  @override
  String get inviteLoadFailed => 'Could not load this invitation.';

  @override
  String get inviteAcceptFailed => 'Could not accept this invitation.';

  @override
  String get worldStillPreparing =>
      'This world is still preparing your account.';

  @override
  String get inviteInvalid =>
      'This invitation is invalid or no longer available.';

  @override
  String get inviteExpired => 'This invitation has expired.';

  @override
  String get networkErrorTryAgain =>
      'Network error. Check your connection and try again.';

  @override
  String get inviteSignInPrompt =>
      'Sign in to review this administrator invitation.';

  @override
  String get signIn => 'Sign in';

  @override
  String get administratorInvitationAccepted =>
      'You are now a note administrator. Your home world has not changed.';

  @override
  String get switchWorldAndOpenNote => 'Switch world and open note';

  @override
  String get goToMap => 'Go to map';

  @override
  String get administratorInvitationExplanation =>
      'Accepting lets you read and administer this note remotely. Posting, likes, and visits still follow the normal location rules.';

  @override
  String get switchWorldAfterAcceptance =>
      'Switch to this world after accepting';

  @override
  String get acceptAdministratorInvitation => 'Accept administrator invitation';

  @override
  String get administratorManageDescription =>
      'Invite a specific user to help administer this note. Administrator access does not grant ordinary remote posting.';

  @override
  String get targetUserIdLabel => 'Target user ID';

  @override
  String get sendAdministratorInvitation => 'Invite administrator';

  @override
  String get administratorInviteCreated => 'Administrator invitation created.';

  @override
  String get inviteCreateFailed => 'Could not create the invitation.';

  @override
  String get administratorInviteRevoked => 'Administrator invitation revoked.';

  @override
  String get inviteRevokeFailed => 'Could not revoke the invitation.';

  @override
  String get administratorRemoved => 'Administrator access removed.';

  @override
  String get administratorRemoveFailed =>
      'Could not remove administrator access.';

  @override
  String get memberRemoveFailed => 'Could not remove this member.';

  @override
  String get copyLink => 'Copy link';

  @override
  String get copied => 'Copied';

  @override
  String get noteAdministratorsTitle => 'Note administrators';

  @override
  String get pendingAdministratorInvitationsTitle => 'Pending invitations';

  @override
  String get passwordAccessMembersTitle => 'Password access';

  @override
  String get passwordAccessDescription =>
      'These users unlocked the private note with its current password.';

  @override
  String get unlockedWithPassword => 'Unlocked with password';

  @override
  String get removeAccess => 'Remove access';

  @override
  String get noteCreatorLabel => 'Creator';

  @override
  String get noteAdministratorLabel => 'Administrator';

  @override
  String get resignAdministrator => 'Resign as administrator';

  @override
  String get removeAdministrator => 'Remove administrator';

  @override
  String get noPendingInvitations => 'No pending invitations.';

  @override
  String get invitationPending => 'Invitation pending';

  @override
  String get revokeInvitation => 'Revoke invitation';

  @override
  String get authEmailAlreadyRegistered => 'This email is already registered.';

  @override
  String get invalidEmail => 'Enter a valid email address.';

  @override
  String get authInvalidCredentials => 'Email or password is incorrect.';

  @override
  String get authOperationNotAllowed =>
      'Email and password sign-in is currently unavailable.';

  @override
  String get authWeakPassword => 'Choose a stronger password.';

  @override
  String get authFailed => 'Authentication failed. Please try again.';

  @override
  String get authTagline => 'Share your world, one note at a time';

  @override
  String get emailLabel => 'Email';

  @override
  String get requiredField => 'Required';

  @override
  String minimumPasswordLength(int count) {
    return 'Use at least $count characters.';
  }

  @override
  String get createAccount => 'Create Account';

  @override
  String get alreadyHaveAccountSignIn => 'Already have an account? Sign In';

  @override
  String get newHereCreateAccount => 'New here? Create Account';

  @override
  String get orDivider => 'or';

  @override
  String get continueWithGoogle => 'Continue with Google';

  @override
  String get continueWithApple => 'Continue with Apple';

  @override
  String get accountSettingsTitle => 'Account';

  @override
  String get deleteAccountTitle => 'Delete account';

  @override
  String get deleteAccountDescription =>
      'Permanently delete your account and all associated data.';

  @override
  String get deleteAccountWarning =>
      'This permanently deletes your profile and contributions, plus every note you created—including other administrators access and participants messages and images—from every World Notes region. This cannot be undone.';

  @override
  String get deleteAccountSubscriptionWarning =>
      'Deleting your World Notes account does not cancel an App Store subscription. Cancel any active subscription before deleting your account to avoid future charges.';

  @override
  String get currentPasswordLabel => 'Current password';

  @override
  String get deleteAccountConfirm => 'Delete permanently';

  @override
  String get deleteAccountFailed =>
      'Could not delete the account. Confirm your sign-in and try again.';

  @override
  String get webpUnsupported =>
      'Image encoding is not supported on this device.';

  @override
  String messageImageUploadFailed(Object error) {
    return 'Failed to upload the image: $error';
  }

  @override
  String messageSendFailed(Object error) {
    return 'Failed to send the message: $error';
  }

  @override
  String get messageContentHint => 'What\'s happening at this place?';

  @override
  String get newMessageTitle => 'New message';

  @override
  String get sendAction => 'Send';

  @override
  String get chooseFromLibrary => 'Choose from library';

  @override
  String get takePhoto => 'Take a photo';

  @override
  String get postTime => 'Post time';

  @override
  String get thumbnailRenderFailed => 'Could not render the thumbnail preview.';

  @override
  String get mapPinImageTitle => 'Map pin image';

  @override
  String get mapPinCropInstruction =>
      'Drag and pinch to choose the part shown in the pin.';

  @override
  String get zoomOut => 'Zoom out';

  @override
  String get zoomIn => 'Zoom in';

  @override
  String get resetAction => 'Reset';

  @override
  String get useImageAction => 'Use Image';

  @override
  String pinImagePreparationFailed(Object error) {
    return 'Could not prepare the pin image: $error';
  }

  @override
  String get closeAction => 'Close';

  @override
  String notificationsLoadFailed(Object error) {
    return 'Could not load notifications: $error';
  }

  @override
  String get adPrivacyTitle => 'Ad Privacy';

  @override
  String get managePrivacyChoices => 'Manage privacy choices';

  @override
  String get managePrivacyChoicesDescription =>
      'Review or change how your information is used for ads.';

  @override
  String privacyChoicesOpenFailed(Object error) {
    return 'Could not open privacy choices: $error';
  }

  @override
  String get followUpdateFailed => 'Could not update the follow setting.';

  @override
  String profileLoadFailed(Object error) {
    return 'Could not load the profile: $error';
  }

  @override
  String get profileNotFound => 'Profile not found.';

  @override
  String followUnavailable(Object error) {
    return 'Follow unavailable: $error';
  }

  @override
  String get followAction => 'Follow';

  @override
  String get unfollowAction => 'Unfollow';

  @override
  String followListLoadFailed(Object error) {
    return 'Could not load the list: $error';
  }

  @override
  String followerCountLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count followers',
      one: '1 follower',
    );
    return '$_temp0';
  }

  @override
  String get footprintsUpdateFailed => 'Could not update footprints.';

  @override
  String get footprintsTitle => 'Footprints';

  @override
  String get sortLatest => 'Latest';

  @override
  String get visitsLabel => 'Visits';

  @override
  String footprintsLoadFailed(Object error) {
    return 'Could not load footprints: $error';
  }

  @override
  String get newVisitsNotRecorded => 'New visits are not being recorded';

  @override
  String visitCountLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count visits',
      one: '1 visit',
    );
    return '$_temp0';
  }

  @override
  String get cannotWriteHere => 'You cannot write here.';

  @override
  String get cancelScheduledMessageTitle => 'Cancel scheduled message';

  @override
  String get deleteMessageTitle => 'Delete message';

  @override
  String get cancelScheduledMessageConfirmation =>
      'Cancel this scheduled message? Its reserved slot will be freed.';

  @override
  String get deleteMessageConfirmation =>
      'Are you sure you want to delete this message? It will appear as deleted to all users.';

  @override
  String get cancelMessageAction => 'Cancel message';

  @override
  String get deleteAction => 'Delete';

  @override
  String messageDeleteFailed(Object error) {
    return 'Failed to delete the message: $error';
  }

  @override
  String get threadCloseTitle => 'Close this thread?';

  @override
  String get threadCloseConfirmation =>
      'No new messages can be posted once closed. Existing messages stay readable, and you can re-open it later.';

  @override
  String threadCloseFailed(Object error) {
    return 'Failed to close the thread: $error';
  }

  @override
  String threadReopenFailed(Object error) {
    return 'Failed to re-open the thread: $error';
  }

  @override
  String get themeChangeFailed => 'Could not change the theme.';

  @override
  String viewUserProfile(String name) {
    return 'View $name\'s profile';
  }

  @override
  String get showFewerColors => 'Show fewer colors';

  @override
  String get showMoreColors => 'Show more colors';

  @override
  String get colorGreen => 'Green';

  @override
  String get colorBlue => 'Blue';

  @override
  String get colorRed => 'Red';

  @override
  String get colorOrange => 'Orange';

  @override
  String get colorPurple => 'Purple';

  @override
  String get colorTeal => 'Teal';

  @override
  String get colorPink => 'Pink';

  @override
  String get colorBrown => 'Brown';

  @override
  String get colorIndigo => 'Indigo';

  @override
  String get colorCyan => 'Cyan';

  @override
  String get colorLime => 'Lime';

  @override
  String get colorAmber => 'Amber';

  @override
  String get colorDeepOrange => 'Deep orange';

  @override
  String get colorBlueGrey => 'Blue grey';

  @override
  String get messageRemovedByAdministrator =>
      'This message was removed by an administrator.';

  @override
  String get messageDeleted => 'This message has been deleted.';

  @override
  String get sensitiveContent => 'Sensitive content';

  @override
  String get sensitiveMessageWarning =>
      'This message may contain sensitive content.';

  @override
  String get showAnywayAction => 'Show anyway';

  @override
  String get scheduledMessage => 'Scheduled message';

  @override
  String get scheduledLabel => 'Scheduled';

  @override
  String get likeMessage => 'Like message';

  @override
  String get unlikeMessage => 'Unlike message';

  @override
  String get showFewerIcons => 'Show fewer icons';

  @override
  String get showMoreIcons => 'Show more icons';

  @override
  String get pinIconPlace => 'Place';

  @override
  String get pinIconRestaurant => 'Restaurant';

  @override
  String get pinIconPark => 'Park';

  @override
  String get pinIconHome => 'Home';

  @override
  String get pinIconStar => 'Star';

  @override
  String get pinIconPhoto => 'Photo';

  @override
  String get pinIconMusic => 'Music';

  @override
  String get pinIconCoffee => 'Coffee';

  @override
  String get pinIconShopping => 'Shopping';

  @override
  String get pinIconHotel => 'Hotel';

  @override
  String get pinIconDirections => 'Car';

  @override
  String get pinIconHiking => 'Hiking';

  @override
  String get pinIconPets => 'Pets';

  @override
  String get pinIconWork => 'Work';

  @override
  String get pinIconFavorite => 'Favorite';

  @override
  String get mapNotesLoadFailed =>
      'Could not load nearby notes. Please try again.';

  @override
  String get mapNotesRefreshFailed =>
      'Could not refresh nearby notes. Please try again.';

  @override
  String get mapNoteOpenFailedNearby =>
      'Could not open this note. Please try again when you are nearby.';

  @override
  String get commonRefresh => 'Refresh';

  @override
  String get adminAccessRequired => 'Admin access required.';

  @override
  String get moderationOpen => 'Open';

  @override
  String get moderationResolved => 'Resolved';

  @override
  String moderationMarkedAs(String action) {
    return 'Marked as $action.';
  }

  @override
  String get reasonLabel => 'Reason';

  @override
  String get applyAction => 'Apply';

  @override
  String get emptyContent => '(empty)';

  @override
  String reportCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count reports',
      one: '1 report',
    );
    return '$_temp0';
  }

  @override
  String get moderationAllowAction => 'Allow';

  @override
  String get moderationSensitiveAction => 'Sensitive';

  @override
  String get moderationHideAction => 'Hide';

  @override
  String get moderationAllowedStatus => 'allowed';

  @override
  String get moderationSensitiveStatus => 'sensitive';

  @override
  String get moderationHiddenStatus => 'hidden';

  @override
  String get moderationAllowTitle => 'Allow message';

  @override
  String get moderationSensitiveTitle => 'Mark sensitive';

  @override
  String get moderationHideTitle => 'Hide message';
}
