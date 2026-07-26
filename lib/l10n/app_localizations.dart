import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_ko.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ja'),
    Locale('ko'),
    Locale('zh'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  ];

  /// Public app name shown in the UI and store listing.
  ///
  /// In en, this message translates to:
  /// **'World Notes'**
  String get appName;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// No description provided for @commonTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get commonTryAgain;

  /// No description provided for @commonError.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String commonError(Object error);

  /// No description provided for @navMap.
  ///
  /// In en, this message translates to:
  /// **'Map'**
  String get navMap;

  /// No description provided for @navNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get navNotes;

  /// No description provided for @navNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get navNotifications;

  /// No description provided for @navProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get navProfile;

  /// No description provided for @locationPermissionTitle.
  ///
  /// In en, this message translates to:
  /// **'Location Required'**
  String get locationPermissionTitle;

  /// No description provided for @locationPermissionMessage.
  ///
  /// In en, this message translates to:
  /// **'Enable location tracking to enjoy World Notes.'**
  String get locationPermissionMessage;

  /// No description provided for @locationPermissionOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get locationPermissionOpenSettings;

  /// No description provided for @locationPermissionAllow.
  ///
  /// In en, this message translates to:
  /// **'Allow Location'**
  String get locationPermissionAllow;

  /// No description provided for @locationServiceDisabledTitle.
  ///
  /// In en, this message translates to:
  /// **'Turn On Location Services'**
  String get locationServiceDisabledTitle;

  /// No description provided for @locationServiceDisabledMessage.
  ///
  /// In en, this message translates to:
  /// **'Turn on location services to use World Notes.'**
  String get locationServiceDisabledMessage;

  /// No description provided for @locationServiceOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Location Settings'**
  String get locationServiceOpenSettings;

  /// No description provided for @locationSearching.
  ///
  /// In en, this message translates to:
  /// **'Finding your location…'**
  String get locationSearching;

  /// No description provided for @locationUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Location unavailable.'**
  String get locationUnavailable;

  /// No description provided for @locationUnavailableHelp.
  ///
  /// In en, this message translates to:
  /// **'Allow location access in Settings,\nor move to an area with better GPS signal.'**
  String get locationUnavailableHelp;

  /// No description provided for @locationLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load location.'**
  String get locationLoadFailed;

  /// No description provided for @currentLocationUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Could not get your current location.'**
  String get currentLocationUnavailable;

  /// No description provided for @enableLocation.
  ///
  /// In en, this message translates to:
  /// **'Enable Location'**
  String get enableLocation;

  /// No description provided for @enableLocationSettingsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Open settings to enable location'**
  String get enableLocationSettingsTooltip;

  /// No description provided for @enableLocationPermissionTooltip.
  ///
  /// In en, this message translates to:
  /// **'Allow location to add notes'**
  String get enableLocationPermissionTooltip;

  /// No description provided for @enableLocationServiceTooltip.
  ///
  /// In en, this message translates to:
  /// **'Open location settings'**
  String get enableLocationServiceTooltip;

  /// No description provided for @mapNotesTitle.
  ///
  /// In en, this message translates to:
  /// **'Map Notes'**
  String get mapNotesTitle;

  /// No description provided for @mapAddNote.
  ///
  /// In en, this message translates to:
  /// **'Add Note'**
  String get mapAddNote;

  /// No description provided for @mapList.
  ///
  /// In en, this message translates to:
  /// **'List'**
  String get mapList;

  /// No description provided for @mapRefreshNotes.
  ///
  /// In en, this message translates to:
  /// **'Refresh map notes'**
  String get mapRefreshNotes;

  /// No description provided for @mapHideAccessArea.
  ///
  /// In en, this message translates to:
  /// **'Hide {radius} access area'**
  String mapHideAccessArea(String radius);

  /// No description provided for @mapShowAccessArea.
  ///
  /// In en, this message translates to:
  /// **'Show {radius} access area'**
  String mapShowAccessArea(String radius);

  /// No description provided for @mapLoadingNotes.
  ///
  /// In en, this message translates to:
  /// **'Loading map notes…'**
  String get mapLoadingNotes;

  /// No description provided for @mapNoNotes.
  ///
  /// In en, this message translates to:
  /// **'No notes in this area.\nMove the map or drop one here!'**
  String get mapNoNotes;

  /// No description provided for @mapDistanceMeters.
  ///
  /// In en, this message translates to:
  /// **'{distance} meters away'**
  String mapDistanceMeters(int distance);

  /// No description provided for @mapDistanceKilometers.
  ///
  /// In en, this message translates to:
  /// **'{distance} km away'**
  String mapDistanceKilometers(String distance);

  /// No description provided for @mapFromFollowing.
  ///
  /// In en, this message translates to:
  /// **'From someone you follow'**
  String get mapFromFollowing;

  /// No description provided for @mapNewFromFollowing.
  ///
  /// In en, this message translates to:
  /// **'New from someone you follow'**
  String get mapNewFromFollowing;

  /// No description provided for @mapFromFollowingSemantic.
  ///
  /// In en, this message translates to:
  /// **'From a followed author.'**
  String get mapFromFollowingSemantic;

  /// No description provided for @newMessages.
  ///
  /// In en, this message translates to:
  /// **'New messages'**
  String get newMessages;

  /// No description provided for @createdAt.
  ///
  /// In en, this message translates to:
  /// **'Created at {date}'**
  String createdAt(String date);

  /// No description provided for @expiresAt.
  ///
  /// In en, this message translates to:
  /// **'Expires {date}'**
  String expiresAt(String date);

  /// No description provided for @noteClosed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get noteClosed;

  /// No description provided for @notePrivate.
  ///
  /// In en, this message translates to:
  /// **'Private'**
  String get notePrivate;

  /// No description provided for @noteWithinRange.
  ///
  /// In en, this message translates to:
  /// **'Within access range. You can open this note.'**
  String get noteWithinRange;

  /// No description provided for @noteOutsideRange.
  ///
  /// In en, this message translates to:
  /// **'Outside access range. Move closer to open this note.'**
  String get noteOutsideRange;

  /// No description provided for @noteOpenNow.
  ///
  /// In en, this message translates to:
  /// **'Open now'**
  String get noteOpenNow;

  /// No description provided for @noteMoveCloser.
  ///
  /// In en, this message translates to:
  /// **'Move closer to open'**
  String get noteMoveCloser;

  /// No description provided for @messageCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 message} other{{count} messages}}'**
  String messageCount(int count);

  /// No description provided for @likeCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 like} other{{count} likes}}'**
  String likeCount(int count);

  /// No description provided for @footprintCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 footprint} other{{count} footprints}}'**
  String footprintCount(int count);

  /// No description provided for @footprintsOn.
  ///
  /// In en, this message translates to:
  /// **'Footprints on'**
  String get footprintsOn;

  /// No description provided for @footprintsOff.
  ///
  /// In en, this message translates to:
  /// **'Footprints off'**
  String get footprintsOff;

  /// No description provided for @noteOpening.
  ///
  /// In en, this message translates to:
  /// **'Opening…'**
  String get noteOpening;

  /// No description provided for @noteView.
  ///
  /// In en, this message translates to:
  /// **'View Note'**
  String get noteView;

  /// No description provided for @noteOpen.
  ///
  /// In en, this message translates to:
  /// **'Open Note'**
  String get noteOpen;

  /// No description provided for @noteAvailableNearby.
  ///
  /// In en, this message translates to:
  /// **'Available nearby'**
  String get noteAvailableNearby;

  /// No description provided for @noteExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get noteExpired;

  /// No description provided for @noteExpiresMonths.
  ///
  /// In en, this message translates to:
  /// **'Expires in {count} months'**
  String noteExpiresMonths(int count);

  /// No description provided for @noteExpiresDays.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Expires in 1 day} other{Expires in {count} days}}'**
  String noteExpiresDays(int count);

  /// No description provided for @noteExpiresHours.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Expires in 1 hour} other{Expires in {count} hours}}'**
  String noteExpiresHours(int count);

  /// No description provided for @noteExpiresSoon.
  ///
  /// In en, this message translates to:
  /// **'Expires soon'**
  String get noteExpiresSoon;

  /// No description provided for @goPro.
  ///
  /// In en, this message translates to:
  /// **'Go PRO'**
  String get goPro;

  /// No description provided for @threadOptions.
  ///
  /// In en, this message translates to:
  /// **'Thread options'**
  String get threadOptions;

  /// No description provided for @writeMessage.
  ///
  /// In en, this message translates to:
  /// **'Write a message'**
  String get writeMessage;

  /// No description provided for @likeNote.
  ///
  /// In en, this message translates to:
  /// **'Like note'**
  String get likeNote;

  /// No description provided for @unlikeNote.
  ///
  /// In en, this message translates to:
  /// **'Unlike note'**
  String get unlikeNote;

  /// No description provided for @cannotLikeOwnNote.
  ///
  /// In en, this message translates to:
  /// **'You cannot like your own note'**
  String get cannotLikeOwnNote;

  /// No description provided for @likeUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Like unavailable'**
  String get likeUnavailable;

  /// No description provided for @noMessages.
  ///
  /// In en, this message translates to:
  /// **'No messages yet.\nBe the first to write!'**
  String get noMessages;

  /// No description provided for @noNotifications.
  ///
  /// In en, this message translates to:
  /// **'No notifications yet.'**
  String get noNotifications;

  /// No description provided for @noFollowers.
  ///
  /// In en, this message translates to:
  /// **'No followers yet.'**
  String get noFollowers;

  /// No description provided for @noFollowing.
  ///
  /// In en, this message translates to:
  /// **'Not following anyone yet.'**
  String get noFollowing;

  /// No description provided for @noFootprints.
  ///
  /// In en, this message translates to:
  /// **'No footprints yet.'**
  String get noFootprints;

  /// No description provided for @noFootprintsDescription.
  ///
  /// In en, this message translates to:
  /// **'Visitors will appear here after they open this note.'**
  String get noFootprintsDescription;

  /// No description provided for @noAccessMembers.
  ///
  /// In en, this message translates to:
  /// **'No one has access yet. Share the link to add people.'**
  String get noAccessMembers;

  /// No description provided for @noModerationReviews.
  ///
  /// In en, this message translates to:
  /// **'No reviews.'**
  String get noModerationReviews;

  /// No description provided for @youLabel.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get youLabel;

  /// No description provided for @messageSending.
  ///
  /// In en, this message translates to:
  /// **'Sending…'**
  String get messageSending;

  /// No description provided for @messageScheduledAt.
  ///
  /// In en, this message translates to:
  /// **'Scheduled {time}'**
  String messageScheduledAt(String time);

  /// No description provided for @reportMessageAction.
  ///
  /// In en, this message translates to:
  /// **'Report message'**
  String get reportMessageAction;

  /// No description provided for @reportNoteAction.
  ///
  /// In en, this message translates to:
  /// **'Report note'**
  String get reportNoteAction;

  /// No description provided for @reportMessageTitle.
  ///
  /// In en, this message translates to:
  /// **'Report message'**
  String get reportMessageTitle;

  /// No description provided for @reportNoteTitle.
  ///
  /// In en, this message translates to:
  /// **'Report note'**
  String get reportNoteTitle;

  /// No description provided for @reportMessageQuestion.
  ///
  /// In en, this message translates to:
  /// **'Why are you reporting this message?'**
  String get reportMessageQuestion;

  /// No description provided for @reportNoteQuestion.
  ///
  /// In en, this message translates to:
  /// **'Why are you reporting this note?'**
  String get reportNoteQuestion;

  /// No description provided for @reportReasonSpam.
  ///
  /// In en, this message translates to:
  /// **'Spam or advertising'**
  String get reportReasonSpam;

  /// No description provided for @reportReasonHarassment.
  ///
  /// In en, this message translates to:
  /// **'Harassment or bullying'**
  String get reportReasonHarassment;

  /// No description provided for @reportReasonSexual.
  ///
  /// In en, this message translates to:
  /// **'Adult or explicit content'**
  String get reportReasonSexual;

  /// No description provided for @reportReasonIllegal.
  ///
  /// In en, this message translates to:
  /// **'Illegal content'**
  String get reportReasonIllegal;

  /// No description provided for @reportReasonOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get reportReasonOther;

  /// No description provided for @reportMessagePrivacy.
  ///
  /// In en, this message translates to:
  /// **'Your user ID, this message ID, the note ID, and the selected reason will be shared with administrators for review.'**
  String get reportMessagePrivacy;

  /// No description provided for @reportNotePrivacy.
  ///
  /// In en, this message translates to:
  /// **'Your user ID, this note ID, and the selected reason will be shared with administrators for review.'**
  String get reportNotePrivacy;

  /// No description provided for @reportSubmitting.
  ///
  /// In en, this message translates to:
  /// **'Submitting...'**
  String get reportSubmitting;

  /// No description provided for @reportSubmitAction.
  ///
  /// In en, this message translates to:
  /// **'Submit report'**
  String get reportSubmitAction;

  /// No description provided for @reportSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Report submitted. Thank you for helping keep this community safe.'**
  String get reportSubmitted;

  /// No description provided for @reportFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to submit report: {error}'**
  String reportFailed(Object error);

  /// No description provided for @reportCooldown.
  ///
  /// In en, this message translates to:
  /// **'Please wait a moment before submitting another report.'**
  String get reportCooldown;

  /// No description provided for @reportUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This content can no longer be reported.'**
  String get reportUnavailable;

  /// No description provided for @contentModerationUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The safety check is temporarily unavailable. Please try again.'**
  String get contentModerationUnavailable;

  /// No description provided for @contentNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'This content cannot be published. Please revise it and try again.'**
  String get contentNotAllowed;

  /// No description provided for @imageNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'This image cannot be used. Please choose another image.'**
  String get imageNotAllowed;

  /// No description provided for @noteCreatedPinImageUploadFailed.
  ///
  /// In en, this message translates to:
  /// **'The note was created, but its pin image could not be uploaded.'**
  String get noteCreatedPinImageUploadFailed;

  /// No description provided for @noteCreateNetworkError.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the server. Check your internet connection and try again.'**
  String get noteCreateNetworkError;

  /// No description provided for @noteCreateAuthenticationRequired.
  ///
  /// In en, this message translates to:
  /// **'Please sign in again to create a note.'**
  String get noteCreateAuthenticationRequired;

  /// No description provided for @noteCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not create the note. Please try again.'**
  String get noteCreateFailed;

  /// No description provided for @noteCreateUnexpectedError.
  ///
  /// In en, this message translates to:
  /// **'An unexpected error occurred. Please try again.'**
  String get noteCreateUnexpectedError;

  /// No description provided for @noteCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'New Note'**
  String get noteCreateTitle;

  /// No description provided for @noteTitleLabel.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get noteTitleLabel;

  /// No description provided for @noteTitleHint.
  ///
  /// In en, this message translates to:
  /// **'What is this place?'**
  String get noteTitleHint;

  /// No description provided for @noteTitleRequired.
  ///
  /// In en, this message translates to:
  /// **'Title is required'**
  String get noteTitleRequired;

  /// No description provided for @noteDescriptionOptionalLabel.
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get noteDescriptionOptionalLabel;

  /// No description provided for @noteDescriptionHint.
  ///
  /// In en, this message translates to:
  /// **'Tell us about this place…'**
  String get noteDescriptionHint;

  /// No description provided for @noteThemeLabel.
  ///
  /// In en, this message translates to:
  /// **'Note theme'**
  String get noteThemeLabel;

  /// No description provided for @noteThemeChangeTitle.
  ///
  /// In en, this message translates to:
  /// **'Change theme'**
  String get noteThemeChangeTitle;

  /// No description provided for @noteThemeChangeDescription.
  ///
  /// In en, this message translates to:
  /// **'This changes the note appearance for everyone.'**
  String get noteThemeChangeDescription;

  /// No description provided for @pinColorLabel.
  ///
  /// In en, this message translates to:
  /// **'Pin color'**
  String get pinColorLabel;

  /// No description provided for @pinStyleLabel.
  ///
  /// In en, this message translates to:
  /// **'Pin style'**
  String get pinStyleLabel;

  /// No description provided for @pinImageLabel.
  ///
  /// In en, this message translates to:
  /// **'Pin image'**
  String get pinImageLabel;

  /// No description provided for @iconLabel.
  ///
  /// In en, this message translates to:
  /// **'Icon'**
  String get iconLabel;

  /// No description provided for @imageLabel.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get imageLabel;

  /// No description provided for @publishLabel.
  ///
  /// In en, this message translates to:
  /// **'Publish'**
  String get publishLabel;

  /// No description provided for @publishNow.
  ///
  /// In en, this message translates to:
  /// **'Now'**
  String get publishNow;

  /// No description provided for @publishLater.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get publishLater;

  /// No description provided for @publishLaterSchedule.
  ///
  /// In en, this message translates to:
  /// **'Publish later'**
  String get publishLaterSchedule;

  /// No description provided for @publishIn15Minutes.
  ///
  /// In en, this message translates to:
  /// **'15 minutes'**
  String get publishIn15Minutes;

  /// No description provided for @publishIn30Minutes.
  ///
  /// In en, this message translates to:
  /// **'30 minutes'**
  String get publishIn30Minutes;

  /// No description provided for @publishIn1Hour.
  ///
  /// In en, this message translates to:
  /// **'1 hour'**
  String get publishIn1Hour;

  /// No description provided for @publishIn3Hours.
  ///
  /// In en, this message translates to:
  /// **'3 hours'**
  String get publishIn3Hours;

  /// No description provided for @publishTomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get publishTomorrow;

  /// No description provided for @publishCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get publishCustom;

  /// No description provided for @autoCloseAfter.
  ///
  /// In en, this message translates to:
  /// **'Auto-close after'**
  String get autoCloseAfter;

  /// No description provided for @autoCloseDescription.
  ///
  /// In en, this message translates to:
  /// **'Stops accepting messages and archives the note after this period.'**
  String get autoCloseDescription;

  /// No description provided for @expiryOneWeek.
  ///
  /// In en, this message translates to:
  /// **'1 week'**
  String get expiryOneWeek;

  /// No description provided for @expiryOneMonth.
  ///
  /// In en, this message translates to:
  /// **'1 month'**
  String get expiryOneMonth;

  /// No description provided for @expiryMonths.
  ///
  /// In en, this message translates to:
  /// **'{count} months'**
  String expiryMonths(int count);

  /// No description provided for @expiryOneYear.
  ///
  /// In en, this message translates to:
  /// **'1 year'**
  String get expiryOneYear;

  /// No description provided for @expiryDays.
  ///
  /// In en, this message translates to:
  /// **'{count} days'**
  String expiryDays(int count);

  /// No description provided for @noteAccessLabel.
  ///
  /// In en, this message translates to:
  /// **'Access'**
  String get noteAccessLabel;

  /// No description provided for @createNoteAction.
  ///
  /// In en, this message translates to:
  /// **'Create Note'**
  String get createNoteAction;

  /// No description provided for @noteCapacityChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking available note slots…'**
  String get noteCapacityChecking;

  /// No description provided for @noteLimitReached.
  ///
  /// In en, this message translates to:
  /// **'Note limit reached'**
  String get noteLimitReached;

  /// No description provided for @premiumNoteLimitMessage.
  ///
  /// In en, this message translates to:
  /// **'You have {count} of {limit} active notes. Archive one or wait for one to expire before creating another.'**
  String premiumNoteLimitMessage(int count, int limit);

  /// No description provided for @freeNoteLimitMessage.
  ///
  /// In en, this message translates to:
  /// **'Free accounts can keep {limit} active notes. Archive one or upgrade to PRO for up to {proLimit}.'**
  String freeNoteLimitMessage(int limit, int proLimit);

  /// No description provided for @forkLocationNotice.
  ///
  /// In en, this message translates to:
  /// **'This new note will use the archived note\'\'s location.'**
  String get forkLocationNotice;

  /// No description provided for @noteCreateLocationPermissionRequired.
  ///
  /// In en, this message translates to:
  /// **'Location permission is required to create a note.'**
  String get noteCreateLocationPermissionRequired;

  /// No description provided for @noteCreateLocationPermissionDisabledMessage.
  ///
  /// In en, this message translates to:
  /// **'Location permission is disabled. Open system settings and allow location access to create notes.'**
  String get noteCreateLocationPermissionDisabledMessage;

  /// No description provided for @noteCreateLocationServiceDisabledMessage.
  ///
  /// In en, this message translates to:
  /// **'Location services are turned off. Turn them on to create a note at your current location.'**
  String get noteCreateLocationServiceDisabledMessage;

  /// No description provided for @noteCreateLocationUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Could not get your current location. Please try again.'**
  String get noteCreateLocationUnavailable;

  /// No description provided for @imagePin.
  ///
  /// In en, this message translates to:
  /// **'Image pin'**
  String get imagePin;

  /// No description provided for @imagePinReady.
  ///
  /// In en, this message translates to:
  /// **'Image pin ready'**
  String get imagePinReady;

  /// No description provided for @pinImageEmptyDescription.
  ///
  /// In en, this message translates to:
  /// **'Add a cropped thumbnail. The default pin is used as fallback.'**
  String get pinImageEmptyDescription;

  /// No description provided for @pinImageReadyDescription.
  ///
  /// In en, this message translates to:
  /// **'This cropped thumbnail will be uploaded.'**
  String get pinImageReadyDescription;

  /// No description provided for @chooseImage.
  ///
  /// In en, this message translates to:
  /// **'Choose image'**
  String get chooseImage;

  /// No description provided for @changeImage.
  ///
  /// In en, this message translates to:
  /// **'Change image'**
  String get changeImage;

  /// No description provided for @removeImage.
  ///
  /// In en, this message translates to:
  /// **'Remove image'**
  String get removeImage;

  /// No description provided for @passwordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get passwordLabel;

  /// No description provided for @patternLabel.
  ///
  /// In en, this message translates to:
  /// **'Pattern'**
  String get patternLabel;

  /// No description provided for @publicNote.
  ///
  /// In en, this message translates to:
  /// **'Public note'**
  String get publicNote;

  /// No description provided for @lockedNote.
  ///
  /// In en, this message translates to:
  /// **'Locked note'**
  String get lockedNote;

  /// No description provided for @noteLockSummary.
  ///
  /// In en, this message translates to:
  /// **'{type} lock'**
  String noteLockSummary(String type);

  /// No description provided for @noteLockSummaryWithHint.
  ///
  /// In en, this message translates to:
  /// **'{type} lock with hint'**
  String noteLockSummaryWithHint(String type);

  /// No description provided for @anyoneNearbyCanOpen.
  ///
  /// In en, this message translates to:
  /// **'Anyone nearby can open it.'**
  String get anyoneNearbyCanOpen;

  /// No description provided for @setLock.
  ///
  /// In en, this message translates to:
  /// **'Set lock'**
  String get setLock;

  /// No description provided for @changeLock.
  ///
  /// In en, this message translates to:
  /// **'Change lock'**
  String get changeLock;

  /// No description provided for @removeLock.
  ///
  /// In en, this message translates to:
  /// **'Remove lock'**
  String get removeLock;

  /// No description provided for @noteThemeStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get noteThemeStandard;

  /// No description provided for @noteThemeStandardDescription.
  ///
  /// In en, this message translates to:
  /// **'The calm, familiar World Notes appearance.'**
  String get noteThemeStandardDescription;

  /// No description provided for @noteThemeAurora.
  ///
  /// In en, this message translates to:
  /// **'Aurora'**
  String get noteThemeAurora;

  /// No description provided for @noteThemeAuroraDescription.
  ///
  /// In en, this message translates to:
  /// **'Indigo with aqua and violet light.'**
  String get noteThemeAuroraDescription;

  /// No description provided for @noteThemeCitrus.
  ///
  /// In en, this message translates to:
  /// **'Citrus Pop'**
  String get noteThemeCitrus;

  /// No description provided for @noteThemeCitrusDescription.
  ///
  /// In en, this message translates to:
  /// **'Warm coral, orange, and a teal lift.'**
  String get noteThemeCitrusDescription;

  /// No description provided for @noteThemeBotanical.
  ///
  /// In en, this message translates to:
  /// **'Botanical'**
  String get noteThemeBotanical;

  /// No description provided for @noteThemeBotanicalDescription.
  ///
  /// In en, this message translates to:
  /// **'Grounded jade and leaf green.'**
  String get noteThemeBotanicalDescription;

  /// No description provided for @noteThemeNeon.
  ///
  /// In en, this message translates to:
  /// **'Neon Grid'**
  String get noteThemeNeon;

  /// No description provided for @noteThemeNeonDescription.
  ///
  /// In en, this message translates to:
  /// **'Cyber cyan and fuchsia after dark.'**
  String get noteThemeNeonDescription;

  /// No description provided for @noteThemeEditorial.
  ///
  /// In en, this message translates to:
  /// **'Editorial'**
  String get noteThemeEditorial;

  /// No description provided for @noteThemeEditorialDescription.
  ///
  /// In en, this message translates to:
  /// **'Paper neutrals with a cobalt signal.'**
  String get noteThemeEditorialDescription;

  /// No description provided for @noteFallbackTitle.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get noteFallbackTitle;

  /// No description provided for @noteUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'This note is not available.'**
  String get noteUnavailableTitle;

  /// No description provided for @noteUnavailableMessage.
  ///
  /// In en, this message translates to:
  /// **'It may not be published yet, may have expired, or may no longer be accessible from here.'**
  String get noteUnavailableMessage;

  /// No description provided for @noteOpenFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Could not open this note.'**
  String get noteOpenFailedTitle;

  /// No description provided for @noteOpenFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Check your connection and make sure you are still nearby.'**
  String get noteOpenFailedMessage;

  /// No description provided for @noteReadOnlyFromMyNotes.
  ///
  /// In en, this message translates to:
  /// **'Read-only from My Notes.'**
  String get noteReadOnlyFromMyNotes;

  /// No description provided for @notePrivateTitle.
  ///
  /// In en, this message translates to:
  /// **'This note is private'**
  String get notePrivateTitle;

  /// No description provided for @notePrivatePasswordDescription.
  ///
  /// In en, this message translates to:
  /// **'Enter the password to read and post messages.'**
  String get notePrivatePasswordDescription;

  /// No description provided for @notePrivatePatternDescription.
  ///
  /// In en, this message translates to:
  /// **'Draw the pattern to read and post messages.'**
  String get notePrivatePatternDescription;

  /// No description provided for @notePrivateDescription.
  ///
  /// In en, this message translates to:
  /// **'Unlock this note to read and post messages.'**
  String get notePrivateDescription;

  /// No description provided for @enterPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter password'**
  String get enterPassword;

  /// No description provided for @drawPattern.
  ///
  /// In en, this message translates to:
  /// **'Draw pattern'**
  String get drawPattern;

  /// No description provided for @unlockAction.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get unlockAction;

  /// No description provided for @noteLockHint.
  ///
  /// In en, this message translates to:
  /// **'Hint: {hint}'**
  String noteLockHint(String hint);

  /// No description provided for @noteScheduledReadOnly.
  ///
  /// In en, this message translates to:
  /// **'This note is scheduled and is not accepting messages yet.'**
  String get noteScheduledReadOnly;

  /// No description provided for @noteArchivedReadOnly.
  ///
  /// In en, this message translates to:
  /// **'This note has been archived. It is read-only.'**
  String get noteArchivedReadOnly;

  /// No description provided for @threadMessageLimitReached.
  ///
  /// In en, this message translates to:
  /// **'This thread reached its {count}-message limit and is now closed.'**
  String threadMessageLimitReached(int count);

  /// No description provided for @threadFullClosed.
  ///
  /// In en, this message translates to:
  /// **'This thread is full and closed.'**
  String get threadFullClosed;

  /// No description provided for @threadMaintainerClosed.
  ///
  /// In en, this message translates to:
  /// **'A maintainer closed this thread. It is read-only.'**
  String get threadMaintainerClosed;

  /// No description provided for @closeThreadAction.
  ///
  /// In en, this message translates to:
  /// **'Close thread'**
  String get closeThreadAction;

  /// No description provided for @reopenThreadAction.
  ///
  /// In en, this message translates to:
  /// **'Re-open thread'**
  String get reopenThreadAction;

  /// No description provided for @changeThemeAction.
  ///
  /// In en, this message translates to:
  /// **'Change theme'**
  String get changeThemeAction;

  /// No description provided for @manageAccessAction.
  ///
  /// In en, this message translates to:
  /// **'Manage access'**
  String get manageAccessAction;

  /// No description provided for @sortNotesTooltip.
  ///
  /// In en, this message translates to:
  /// **'Sort notes: {sort}'**
  String sortNotesTooltip(String sort);

  /// No description provided for @sortNotesSelected.
  ///
  /// In en, this message translates to:
  /// **'Sort notes. {sort} selected'**
  String sortNotesSelected(String sort);

  /// No description provided for @sortedBy.
  ///
  /// In en, this message translates to:
  /// **'Sorted by: {sort}'**
  String sortedBy(String sort);

  /// No description provided for @sortDistance.
  ///
  /// In en, this message translates to:
  /// **'Distance'**
  String get sortDistance;

  /// No description provided for @sortLastActivity.
  ///
  /// In en, this message translates to:
  /// **'Last activity'**
  String get sortLastActivity;

  /// No description provided for @sortNewest.
  ///
  /// In en, this message translates to:
  /// **'Newest'**
  String get sortNewest;

  /// No description provided for @sortExpiresSoon.
  ///
  /// In en, this message translates to:
  /// **'Expires soon'**
  String get sortExpiresSoon;

  /// No description provided for @sortMostLiked.
  ///
  /// In en, this message translates to:
  /// **'Most liked'**
  String get sortMostLiked;

  /// No description provided for @sortArchivedNewest.
  ///
  /// In en, this message translates to:
  /// **'Recently archived'**
  String get sortArchivedNewest;

  /// No description provided for @sortArchivedOldest.
  ///
  /// In en, this message translates to:
  /// **'Oldest archived'**
  String get sortArchivedOldest;

  /// No description provided for @myNotesTitle.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get myNotesTitle;

  /// No description provided for @myNotesTab.
  ///
  /// In en, this message translates to:
  /// **'My Notes'**
  String get myNotesTab;

  /// No description provided for @archivedNotesTab.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get archivedNotesTab;

  /// No description provided for @archiveNoteTitle.
  ///
  /// In en, this message translates to:
  /// **'Archive this note?'**
  String get archiveNoteTitle;

  /// No description provided for @archiveNoteMessage.
  ///
  /// In en, this message translates to:
  /// **'It will disappear from the map, become read-only, and free one note slot. You cannot restore the archived note, but you can create a new note from its title, description, and location later.'**
  String get archiveNoteMessage;

  /// No description provided for @archiveAction.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get archiveAction;

  /// No description provided for @archiveFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to archive note: {error}'**
  String archiveFailed(Object error);

  /// No description provided for @loadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get loadMore;

  /// No description provided for @retryLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Retry loading more'**
  String get retryLoadMore;

  /// No description provided for @createdNotes.
  ///
  /// In en, this message translates to:
  /// **'Created notes'**
  String get createdNotes;

  /// No description provided for @archivedNotes.
  ///
  /// In en, this message translates to:
  /// **'Archived notes'**
  String get archivedNotes;

  /// No description provided for @lastActive.
  ///
  /// In en, this message translates to:
  /// **'Last active {time}'**
  String lastActive(String time);

  /// No description provided for @archivedAt.
  ///
  /// In en, this message translates to:
  /// **'Archived {time}'**
  String archivedAt(String time);

  /// No description provided for @createFromArchiveTooltip.
  ///
  /// In en, this message translates to:
  /// **'Create new note from archive'**
  String get createFromArchiveTooltip;

  /// No description provided for @archiveNoteTooltip.
  ///
  /// In en, this message translates to:
  /// **'Archive note'**
  String get archiveNoteTooltip;

  /// No description provided for @relativeDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day ago} other{{count} days ago}}'**
  String relativeDaysAgo(int count);

  /// No description provided for @relativeHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 hour ago} other{{count} hours ago}}'**
  String relativeHoursAgo(int count);

  /// No description provided for @relativeMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} min ago'**
  String relativeMinutesAgo(int count);

  /// No description provided for @relativeJustNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get relativeJustNow;

  /// No description provided for @noArchivedNotes.
  ///
  /// In en, this message translates to:
  /// **'No archived notes yet.'**
  String get noArchivedNotes;

  /// No description provided for @noMyNotes.
  ///
  /// In en, this message translates to:
  /// **'No notes yet.\nCreate one from the Map tab.'**
  String get noMyNotes;

  /// No description provided for @profileTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileTitle;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsLanguageTitle.
  ///
  /// In en, this message translates to:
  /// **'App Language'**
  String get settingsLanguageTitle;

  /// No description provided for @settingsLanguageSystem.
  ///
  /// In en, this message translates to:
  /// **'Automatic (System)'**
  String get settingsLanguageSystem;

  /// No description provided for @settingsLanguageSystemDescription.
  ///
  /// In en, this message translates to:
  /// **'Use your device language'**
  String get settingsLanguageSystemDescription;

  /// No description provided for @settingsLanguageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settingsLanguageEnglish;

  /// No description provided for @settingsLanguageJapanese.
  ///
  /// In en, this message translates to:
  /// **'日本語'**
  String get settingsLanguageJapanese;

  /// No description provided for @settingsLanguageKorean.
  ///
  /// In en, this message translates to:
  /// **'한국어'**
  String get settingsLanguageKorean;

  /// No description provided for @settingsLanguageSimplifiedChinese.
  ///
  /// In en, this message translates to:
  /// **'简体中文'**
  String get settingsLanguageSimplifiedChinese;

  /// No description provided for @settingsLanguageTraditionalChinese.
  ///
  /// In en, this message translates to:
  /// **'繁體中文'**
  String get settingsLanguageTraditionalChinese;

  /// No description provided for @settingsLanguageUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'The language changed on this device, but could not be saved to your account.'**
  String get settingsLanguageUpdateFailed;

  /// No description provided for @settingsMapStyleTitle.
  ///
  /// In en, this message translates to:
  /// **'Map Style'**
  String get settingsMapStyleTitle;

  /// No description provided for @settingsMapStyleAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get settingsMapStyleAuto;

  /// No description provided for @settingsMapStyleStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get settingsMapStyleStandard;

  /// No description provided for @settingsMapStyleLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsMapStyleLight;

  /// No description provided for @settingsMapStyleDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsMapStyleDark;

  /// No description provided for @settingsMapStylePop.
  ///
  /// In en, this message translates to:
  /// **'Pop'**
  String get settingsMapStylePop;

  /// No description provided for @settingsMapStyleAutoDescription.
  ///
  /// In en, this message translates to:
  /// **'Follow the system appearance'**
  String get settingsMapStyleAutoDescription;

  /// No description provided for @settingsMapStyleStandardDescription.
  ///
  /// In en, this message translates to:
  /// **'Clean & minimal'**
  String get settingsMapStyleStandardDescription;

  /// No description provided for @settingsMapStyleLightDescription.
  ///
  /// In en, this message translates to:
  /// **'Use Apple Maps in light mode'**
  String get settingsMapStyleLightDescription;

  /// No description provided for @settingsMapStyleDarkDescription.
  ///
  /// In en, this message translates to:
  /// **'Easy on the eyes at night'**
  String get settingsMapStyleDarkDescription;

  /// No description provided for @settingsMapStylePopDescription.
  ///
  /// In en, this message translates to:
  /// **'Bright & colourful'**
  String get settingsMapStylePopDescription;

  /// No description provided for @settingsDataRegionTitle.
  ///
  /// In en, this message translates to:
  /// **'Data Region'**
  String get settingsDataRegionTitle;

  /// No description provided for @settingsDataRegionDescription.
  ///
  /// In en, this message translates to:
  /// **'Choose which region serves your requests. Auto picks the closest to your current location — handy to override while travelling.'**
  String get settingsDataRegionDescription;

  /// No description provided for @settingsDataRegionAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto (nearest)'**
  String get settingsDataRegionAuto;

  /// No description provided for @settingsDataRegionCurrent.
  ///
  /// In en, this message translates to:
  /// **'Currently: {region}'**
  String settingsDataRegionCurrent(String region);

  /// No description provided for @settingsRegionAsiaTokyo.
  ///
  /// In en, this message translates to:
  /// **'Asia (Tokyo)'**
  String get settingsRegionAsiaTokyo;

  /// No description provided for @settingsRegionAmericasUsCentral.
  ///
  /// In en, this message translates to:
  /// **'Americas (US Central)'**
  String get settingsRegionAmericasUsCentral;

  /// No description provided for @settingsRegionEuropeBelgium.
  ///
  /// In en, this message translates to:
  /// **'Europe (Belgium)'**
  String get settingsRegionEuropeBelgium;

  /// No description provided for @settingsNotificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get settingsNotificationsTitle;

  /// No description provided for @notificationsMaintainedNotesTitle.
  ///
  /// In en, this message translates to:
  /// **'Maintained notes'**
  String get notificationsMaintainedNotesTitle;

  /// No description provided for @notificationsMaintainedNotesDescription.
  ///
  /// In en, this message translates to:
  /// **'Receive notifications when notes you maintain get new messages.'**
  String get notificationsMaintainedNotesDescription;

  /// No description provided for @notificationsTurnOnTooltip.
  ///
  /// In en, this message translates to:
  /// **'Turn on maintained-note notifications'**
  String get notificationsTurnOnTooltip;

  /// No description provided for @notificationsTurnOffTooltip.
  ///
  /// In en, this message translates to:
  /// **'Turn off maintained-note notifications'**
  String get notificationsTurnOffTooltip;

  /// No description provided for @notificationsPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Notifications are not allowed. Enable notifications in system settings to receive new message alerts.'**
  String get notificationsPermissionDenied;

  /// No description provided for @notificationsEnableFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not enable maintained-note notifications.'**
  String get notificationsEnableFailed;

  /// No description provided for @notificationsDisableFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not disable maintained-note notifications.'**
  String get notificationsDisableFailed;

  /// No description provided for @notificationPreviewsTitle.
  ///
  /// In en, this message translates to:
  /// **'Message previews'**
  String get notificationPreviewsTitle;

  /// No description provided for @notificationPreviewsDescription.
  ///
  /// In en, this message translates to:
  /// **'Show message text in maintained-note alerts.'**
  String get notificationPreviewsDescription;

  /// No description provided for @notificationPreviewsUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not update notification previews.'**
  String get notificationPreviewsUpdateFailed;

  /// No description provided for @editNickname.
  ///
  /// In en, this message translates to:
  /// **'Edit nickname'**
  String get editNickname;

  /// No description provided for @nicknameLabel.
  ///
  /// In en, this message translates to:
  /// **'Nickname'**
  String get nicknameLabel;

  /// No description provided for @nicknameUpdated.
  ///
  /// In en, this message translates to:
  /// **'Nickname updated.'**
  String get nicknameUpdated;

  /// No description provided for @nicknameUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to update nickname: {error}'**
  String nicknameUpdateFailed(Object error);

  /// No description provided for @manageSubscription.
  ///
  /// In en, this message translates to:
  /// **'Manage Subscription'**
  String get manageSubscription;

  /// No description provided for @upgradeToPro.
  ///
  /// In en, this message translates to:
  /// **'Upgrade to PRO'**
  String get upgradeToPro;

  /// No description provided for @proBenefitsSummary.
  ///
  /// In en, this message translates to:
  /// **'Remove ads, keep 200 notes, and unlock PRO features'**
  String get proBenefitsSummary;

  /// No description provided for @subscriptionManagementSummary.
  ///
  /// In en, this message translates to:
  /// **'Billing, cancellation & support'**
  String get subscriptionManagementSummary;

  /// No description provided for @proHeroTitle.
  ///
  /// In en, this message translates to:
  /// **'Make every place memorable'**
  String get proHeroTitle;

  /// No description provided for @proHeroSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Unlock more ways to leave, revisit, and share notes around the world.'**
  String get proHeroSubtitle;

  /// No description provided for @proFeatureAdFree.
  ///
  /// In en, this message translates to:
  /// **'Enjoy World Notes without ads'**
  String get proFeatureAdFree;

  /// No description provided for @proFeatureNoteLimit.
  ///
  /// In en, this message translates to:
  /// **'Keep up to {count} active notes'**
  String proFeatureNoteLimit(int count);

  /// No description provided for @proFeatureAccessArea.
  ///
  /// In en, this message translates to:
  /// **'Open nearby notes from a wider area'**
  String get proFeatureAccessArea;

  /// No description provided for @proMonthlyPlan.
  ///
  /// In en, this message translates to:
  /// **'{price} / month'**
  String proMonthlyPlan(String price);

  /// No description provided for @proYearlyPlan.
  ///
  /// In en, this message translates to:
  /// **'{price} / year'**
  String proYearlyPlan(String price);

  /// No description provided for @proIntroOffer.
  ///
  /// In en, this message translates to:
  /// **'First year {price}'**
  String proIntroOffer(String price);

  /// No description provided for @proChoosePlan.
  ///
  /// In en, this message translates to:
  /// **'Choose your PRO plan'**
  String get proChoosePlan;

  /// No description provided for @moderation.
  ///
  /// In en, this message translates to:
  /// **'Moderation'**
  String get moderation;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign Out'**
  String get signOut;

  /// No description provided for @followers.
  ///
  /// In en, this message translates to:
  /// **'Followers'**
  String get followers;

  /// No description provided for @following.
  ///
  /// In en, this message translates to:
  /// **'Following'**
  String get following;

  /// No description provided for @subscriptionUnavailableBuild.
  ///
  /// In en, this message translates to:
  /// **'{planName} is not available in this build.'**
  String subscriptionUnavailableBuild(String planName);

  /// No description provided for @subscriptionTemporarilyUnavailable.
  ///
  /// In en, this message translates to:
  /// **'{planName} is temporarily unavailable.'**
  String subscriptionTemporarilyUnavailable(String planName);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ja', 'ko', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+script codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.scriptCode) {
          case 'Hans':
            return AppLocalizationsZhHans();
          case 'Hant':
            return AppLocalizationsZhHant();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ja':
      return AppLocalizationsJa();
    case 'ko':
      return AppLocalizationsKo();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
