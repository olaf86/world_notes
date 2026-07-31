// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get appName => '세계 일기';

  @override
  String get commonCancel => '취소';

  @override
  String get commonSave => '저장';

  @override
  String get commonRetry => '다시 시도';

  @override
  String get commonTryAgain => '다시 시도하기';

  @override
  String commonError(Object error) {
    return '오류: $error';
  }

  @override
  String get navMap => '지도';

  @override
  String get navNotes => '노트';

  @override
  String get navNotifications => '알림';

  @override
  String get navProfile => '프로필';

  @override
  String get locationPermissionTitle => '위치 권한이 필요합니다';

  @override
  String get locationPermissionMessage => '세계 일기를 이용하려면 위치 추적을 허용해 주세요.';

  @override
  String get locationPermissionOpenSettings => '설정 열기';

  @override
  String get locationPermissionAllow => '위치 허용';

  @override
  String get locationServiceDisabledTitle => '위치 서비스를 켜 주세요';

  @override
  String get locationServiceDisabledMessage => '세계 일기를 사용하려면 위치 서비스를 켜 주세요.';

  @override
  String get locationServiceOpenSettings => '위치 설정 열기';

  @override
  String get locationSearching => '현재 위치를 찾는 중…';

  @override
  String get locationUnavailable => '위치를 사용할 수 없습니다.';

  @override
  String get locationUnavailableHelp =>
      '설정에서 위치 접근을 허용하거나\nGPS 신호가 더 좋은 곳으로 이동해 주세요.';

  @override
  String get locationLoadFailed => '위치를 불러오지 못했습니다.';

  @override
  String get currentLocationUnavailable => '현재 위치를 가져오지 못했습니다.';

  @override
  String get enableLocation => '위치 활성화';

  @override
  String get enableLocationSettingsTooltip => '설정을 열어 위치 활성화';

  @override
  String get enableLocationPermissionTooltip => '노트를 추가할 수 있도록 위치 허용';

  @override
  String get enableLocationServiceTooltip => '위치 설정 열기';

  @override
  String get mapNotesTitle => '주변 노트';

  @override
  String get mapAddNote => '노트 추가';

  @override
  String get mapList => '목록';

  @override
  String get mapRefreshNotes => '지도 노트 새로고침';

  @override
  String mapHideAccessArea(String radius) {
    return '$radius 접근 범위 숨기기';
  }

  @override
  String mapShowAccessArea(String radius) {
    return '$radius 접근 범위 표시';
  }

  @override
  String get mapLoadingNotes => '주변 노트를 불러오는 중…';

  @override
  String get mapNoNotes => '이 지역에는 아직 노트가 없습니다.\n지도를 움직이거나 여기에 하나 남겨 보세요!';

  @override
  String mapDistanceMeters(int distance) {
    return '${distance}m 거리';
  }

  @override
  String mapDistanceKilometers(String distance) {
    return '${distance}km 거리';
  }

  @override
  String get mapFromFollowing => '팔로우한 사용자의 노트';

  @override
  String get mapNewFromFollowing => '팔로우한 사용자의 새 노트';

  @override
  String get mapFromFollowingSemantic => '팔로우한 작성자가 만든 노트입니다.';

  @override
  String get newMessages => '새 메시지';

  @override
  String createdAt(String date) {
    return '작성 $date';
  }

  @override
  String expiresAt(String date) {
    return '만료 $date';
  }

  @override
  String get noteClosed => '종료됨';

  @override
  String get notePrivate => '비공개';

  @override
  String get noteWithinRange => '접근 범위 안에 있습니다. 이 노트를 열 수 있습니다.';

  @override
  String get noteOutsideRange => '접근 범위 밖에 있습니다. 가까이 이동해 주세요.';

  @override
  String get noteOpenNow => '지금 열기';

  @override
  String get noteMoveCloser => '가까이 이동해 열기';

  @override
  String messageCount(int count) {
    return '메시지 $count개';
  }

  @override
  String likeCount(int count) {
    return '좋아요 $count개';
  }

  @override
  String footprintCount(int count) {
    return '발자국 $count회';
  }

  @override
  String get footprintsOn => '발자국 기록 켜짐';

  @override
  String get footprintsOff => '발자국 기록 꺼짐';

  @override
  String get noteOpening => '여는 중…';

  @override
  String get noteView => '노트 보기';

  @override
  String get noteOpen => '노트 열기';

  @override
  String get noteAvailableNearby => '가까이 가면 열 수 있습니다';

  @override
  String get noteExpired => '만료됨';

  @override
  String noteExpiresMonths(int count) {
    return '$count개월 후 만료';
  }

  @override
  String noteExpiresDays(int count) {
    return '$count일 후 만료';
  }

  @override
  String noteExpiresHours(int count) {
    return '$count시간 후 만료';
  }

  @override
  String get noteExpiresSoon => '곧 만료';

  @override
  String get goPro => 'PRO 시작하기';

  @override
  String get threadOptions => '노트 옵션';

  @override
  String get writeMessage => '메시지 작성';

  @override
  String get likeNote => '노트 좋아요';

  @override
  String get unlikeNote => '노트 좋아요 취소';

  @override
  String get cannotLikeOwnNote => '내 노트에는 좋아요를 누를 수 없습니다';

  @override
  String get likeUnavailable => '좋아요를 사용할 수 없습니다';

  @override
  String get noMessages => '아직 메시지가 없습니다.\n첫 메시지를 남겨 보세요!';

  @override
  String get noNotifications => '아직 알림이 없습니다.';

  @override
  String get noFollowers => '아직 팔로워가 없습니다.';

  @override
  String get noFollowing => '아직 팔로우하는 사람이 없습니다.';

  @override
  String get noFootprints => '아직 발자국이 없습니다.';

  @override
  String get noFootprintsDescription => '방문자가 이 노트를 열면 여기에 표시됩니다.';

  @override
  String get noAccessMembers => '아직 접근 권한이 있는 사람이 없습니다. 링크를 공유해 추가하세요.';

  @override
  String get noModerationReviews => '검토할 항목이 없습니다.';

  @override
  String get youLabel => '나';

  @override
  String get messageSending => '전송 중…';

  @override
  String messageScheduledAt(String time) {
    return '$time에 게시 예정';
  }

  @override
  String get reportMessageAction => '메시지 신고';

  @override
  String get reportNoteAction => '노트 신고';

  @override
  String get reportMessageTitle => '메시지 신고';

  @override
  String get reportNoteTitle => '노트 신고';

  @override
  String get reportMessageQuestion => '이 메시지를 신고하는 이유를 선택하세요.';

  @override
  String get reportNoteQuestion => '이 노트를 신고하는 이유를 선택하세요.';

  @override
  String get reportReasonSpam => '스팸 또는 광고';

  @override
  String get reportReasonHarassment => '괴롭힘 또는 따돌림';

  @override
  String get reportReasonSexual => '성인용 또는 노골적인 콘텐츠';

  @override
  String get reportReasonIllegal => '불법 콘텐츠';

  @override
  String get reportReasonOther => '기타';

  @override
  String get reportMessagePrivacy =>
      '검토를 위해 사용자 ID, 메시지 ID, 노트 ID 및 선택한 사유가 관리자에게 공유됩니다.';

  @override
  String get reportNotePrivacy => '검토를 위해 사용자 ID, 노트 ID 및 선택한 사유가 관리자에게 공유됩니다.';

  @override
  String get reportSubmitting => '제출 중...';

  @override
  String get reportSubmitAction => '신고 제출';

  @override
  String get reportSubmitted => '신고가 접수되었습니다. 커뮤니티 안전에 도움을 주셔서 감사합니다.';

  @override
  String get reportAlsoBlockUser => '이 사용자도 차단';

  @override
  String get reportAlsoBlockUserDescription =>
      '신고가 제출되면 이 사용자의 노트와 메시지가 숨겨집니다.';

  @override
  String get reportSubmittedBlockFailed => '신고는 제출되었지만 사용자를 차단하지 못했습니다.';

  @override
  String reportFailed(Object error) {
    return '신고를 제출하지 못했습니다: $error';
  }

  @override
  String get reportCooldown => '잠시 후 다시 신고해 주세요.';

  @override
  String get reportUnavailable => '이 콘텐츠는 더 이상 신고할 수 없습니다.';

  @override
  String get contentModerationUnavailable =>
      '안전성 확인을 일시적으로 사용할 수 없습니다. 다시 시도해 주세요.';

  @override
  String get contentNotAllowed => '이 콘텐츠는 게시할 수 없습니다. 수정한 후 다시 시도해 주세요.';

  @override
  String get imageNotAllowed => '이 이미지는 사용할 수 없습니다. 다른 이미지를 선택해 주세요.';

  @override
  String get noteCreatedPinImageUploadFailed =>
      '노트는 생성되었지만 핀 이미지를 업로드하지 못했습니다.';

  @override
  String get noteCreateNetworkError =>
      '서버에 연결할 수 없습니다. 인터넷 연결을 확인한 후 다시 시도해 주세요.';

  @override
  String get noteCreateAuthenticationRequired => '노트를 만들려면 다시 로그인해 주세요.';

  @override
  String get noteCreateFailed => '노트를 만들지 못했습니다. 다시 시도해 주세요.';

  @override
  String get noteCreateUnexpectedError => '예기치 않은 오류가 발생했습니다. 다시 시도해 주세요.';

  @override
  String get noteCreateTitle => '새 노트';

  @override
  String get noteTitleLabel => '제목';

  @override
  String get noteTitleHint => '어떤 장소인가요?';

  @override
  String get noteTitleRequired => '제목을 입력해 주세요';

  @override
  String get noteDescriptionOptionalLabel => '설명(선택 사항)';

  @override
  String get noteDescriptionHint => '이 장소에 대해 알려 주세요…';

  @override
  String get noteThemeLabel => '노트 테마';

  @override
  String get noteThemeChangeTitle => '테마 변경';

  @override
  String get noteThemeChangeDescription =>
      '이 변경 사항은 모든 사용자에게 표시되는 노트 디자인에 적용됩니다.';

  @override
  String get pinColorLabel => '핀 색상';

  @override
  String get pinStyleLabel => '핀 스타일';

  @override
  String get pinImageLabel => '핀 이미지';

  @override
  String get iconLabel => '아이콘';

  @override
  String get imageLabel => '이미지';

  @override
  String get publishLabel => '게시';

  @override
  String get publishNow => '지금';

  @override
  String get publishLater => '나중에';

  @override
  String get publishLaterSchedule => '나중에 게시';

  @override
  String get publishIn15Minutes => '15분 후';

  @override
  String get publishIn30Minutes => '30분 후';

  @override
  String get publishIn1Hour => '1시간 후';

  @override
  String get publishIn3Hours => '3시간 후';

  @override
  String get publishTomorrow => '내일';

  @override
  String get publishCustom => '직접 설정';

  @override
  String get autoCloseAfter => '자동 종료';

  @override
  String get autoCloseDescription => '이 기간이 지나면 메시지 수신을 중단하고 노트를 보관합니다.';

  @override
  String get expiryOneWeek => '1주';

  @override
  String get expiryOneMonth => '1개월';

  @override
  String expiryMonths(int count) {
    return '$count개월';
  }

  @override
  String get expiryOneYear => '1년';

  @override
  String expiryDays(int count) {
    return '$count일';
  }

  @override
  String get noteAccessLabel => '접근';

  @override
  String get createNoteAction => '노트 만들기';

  @override
  String get noteCapacityChecking => '사용 가능한 노트 수를 확인하는 중…';

  @override
  String get noteLimitReached => '노트 한도에 도달했습니다';

  @override
  String premiumNoteLimitMessage(int count, int limit) {
    return '활성 노트 $limit개 중 $count개를 사용 중입니다. 새 노트를 만들려면 하나를 보관하거나 만료될 때까지 기다려 주세요.';
  }

  @override
  String freeNoteLimitMessage(int limit, int proLimit) {
    return '무료 계정은 활성 노트를 $limit개까지 보관할 수 있습니다. 하나를 보관하거나 PRO로 업그레이드하면 최대 $proLimit개까지 이용할 수 있습니다.';
  }

  @override
  String get forkLocationNotice => '보관된 노트의 위치를 사용해 새 노트를 만듭니다.';

  @override
  String get noteCreateLocationPermissionRequired => '노트를 만들려면 위치 권한이 필요합니다.';

  @override
  String get noteCreateLocationPermissionDisabledMessage =>
      '위치 권한이 비활성화되어 있습니다. 시스템 설정을 열어 노트를 만들 수 있도록 위치 접근을 허용해 주세요.';

  @override
  String get noteCreateLocationServiceDisabledMessage =>
      '위치 서비스가 꺼져 있습니다. 현재 위치에 노트를 만들려면 켜 주세요.';

  @override
  String get noteCreateLocationUnavailable => '현재 위치를 가져올 수 없습니다. 다시 시도해 주세요.';

  @override
  String get imagePin => '이미지 핀';

  @override
  String get imagePinReady => '이미지 핀 준비 완료';

  @override
  String get pinImageEmptyDescription =>
      '잘라낸 썸네일을 추가하세요. 설정하지 않으면 기본 핀이 사용됩니다.';

  @override
  String get pinImageReadyDescription => '이 썸네일이 업로드됩니다.';

  @override
  String get chooseImage => '이미지 선택';

  @override
  String get changeImage => '이미지 변경';

  @override
  String get removeImage => '이미지 삭제';

  @override
  String get passwordLabel => '비밀번호';

  @override
  String get patternLabel => '패턴';

  @override
  String get publicNote => '공개 노트';

  @override
  String get lockedNote => '잠긴 노트';

  @override
  String noteLockSummary(String type) {
    return '$type 잠금';
  }

  @override
  String noteLockSummaryWithHint(String type) {
    return '힌트가 있는 $type 잠금';
  }

  @override
  String get anyoneNearbyCanOpen => '근처에 있는 누구나 열 수 있습니다.';

  @override
  String get setLock => '잠금 설정';

  @override
  String get changeLock => '잠금 변경';

  @override
  String get removeLock => '잠금 해제';

  @override
  String get noteThemeStandard => '스탠다드';

  @override
  String get noteThemeStandardDescription => '차분하고 익숙한 World Notes 기본 디자인.';

  @override
  String get noteThemeAurora => '오로라';

  @override
  String get noteThemeAuroraDescription => '인디고에 아쿠아와 바이올렛 빛을 더한 디자인.';

  @override
  String get noteThemeCitrus => '시트러스 팝';

  @override
  String get noteThemeCitrusDescription => '따뜻한 코랄과 오렌지에 틸 포인트.';

  @override
  String get noteThemeBotanical => '보태니컬';

  @override
  String get noteThemeBotanicalDescription => '차분한 비취색과 잎사귀 초록.';

  @override
  String get noteThemeNeon => '네온 그리드';

  @override
  String get noteThemeNeonDescription => '어둠 속에서 빛나는 사이언과 푸크시아.';

  @override
  String get noteThemeEditorial => '에디토리얼';

  @override
  String get noteThemeEditorialDescription => '종이 느낌의 중간색과 코발트 포인트.';

  @override
  String get noteFallbackTitle => '노트';

  @override
  String get noteUnavailableTitle => '이 노트를 사용할 수 없습니다.';

  @override
  String get noteUnavailableMessage =>
      '아직 게시되지 않았거나 만료되었거나 현재 위치에서 더 이상 접근할 수 없을 수 있습니다.';

  @override
  String get noteOpenFailedTitle => '노트를 열 수 없습니다.';

  @override
  String get noteOpenFailedMessage => '연결 상태와 노트 근처에 있는지 확인해 주세요.';

  @override
  String get noteReadOnlyFromMyNotes => '내 노트에서는 읽기 전용입니다.';

  @override
  String get notePrivateTitle => '비공개 노트입니다';

  @override
  String get notePrivatePasswordDescription => '메시지를 읽고 게시하려면 비밀번호를 입력하세요.';

  @override
  String get notePrivatePatternDescription => '메시지를 읽고 게시하려면 패턴을 그리세요.';

  @override
  String get notePrivateDescription => '메시지를 읽고 게시하려면 노트 잠금을 해제하세요.';

  @override
  String get enterPassword => '비밀번호 입력';

  @override
  String get drawPattern => '패턴 그리기';

  @override
  String get unlockAction => '잠금 해제';

  @override
  String noteLockHint(String hint) {
    return '힌트: $hint';
  }

  @override
  String get noteScheduledReadOnly => '이 노트는 게시 예약 중이라 아직 메시지를 받지 않습니다.';

  @override
  String get noteArchivedReadOnly => '이 노트는 보관되었습니다. 읽기 전용입니다.';

  @override
  String threadMessageLimitReached(int count) {
    return '이 스레드는 메시지 한도 $count개에 도달하여 종료되었습니다.';
  }

  @override
  String get threadFullClosed => '이 스레드는 가득 차서 종료되었습니다.';

  @override
  String get threadMaintainerClosed => '관리자가 이 스레드를 종료했습니다. 읽기 전용입니다.';

  @override
  String get closeThreadAction => '스레드 종료';

  @override
  String get reopenThreadAction => '스레드 다시 열기';

  @override
  String get changeThemeAction => '테마 변경';

  @override
  String get manageAccessAction => '접근 관리';

  @override
  String sortNotesTooltip(String sort) {
    return '노트 정렬: $sort';
  }

  @override
  String sortNotesSelected(String sort) {
    return '노트 정렬. $sort 선택됨';
  }

  @override
  String sortedBy(String sort) {
    return '정렬 기준: $sort';
  }

  @override
  String get sortDistance => '거리순';

  @override
  String get sortLastActivity => '최근 활동순';

  @override
  String get sortNewest => '최신 작성순';

  @override
  String get sortExpiresSoon => '만료 임박순';

  @override
  String get sortMostLiked => '좋아요순';

  @override
  String get sortArchivedNewest => '최근 보관순';

  @override
  String get sortArchivedOldest => '오래된 보관순';

  @override
  String get myNotesTitle => '노트';

  @override
  String get myNotesTab => '내 노트';

  @override
  String get archivedNotesTab => '보관함';

  @override
  String get archiveNoteTitle => '이 노트를 보관할까요?';

  @override
  String get archiveNoteMessage =>
      '지도에서 사라지고 읽기 전용으로 전환되며 노트 슬롯 하나가 비워집니다. 보관한 노트는 복원할 수 없지만 나중에 제목, 설명, 위치를 가져와 새 노트를 만들 수 있습니다.';

  @override
  String get archiveAction => '보관';

  @override
  String archiveFailed(Object error) {
    return '노트를 보관하지 못했습니다: $error';
  }

  @override
  String get loadMore => '더 보기';

  @override
  String get retryLoadMore => '더 보기 다시 시도';

  @override
  String get createdNotes => '작성한 노트';

  @override
  String get archivedNotes => '보관한 노트';

  @override
  String lastActive(String time) {
    return '마지막 활동 $time';
  }

  @override
  String archivedAt(String time) {
    return '$time에 보관';
  }

  @override
  String get createFromArchiveTooltip => '보관한 노트로 새 노트 만들기';

  @override
  String get archiveNoteTooltip => '노트 보관';

  @override
  String relativeDaysAgo(int count) {
    return '$count일 전';
  }

  @override
  String relativeHoursAgo(int count) {
    return '$count시간 전';
  }

  @override
  String relativeMinutesAgo(int count) {
    return '$count분 전';
  }

  @override
  String get relativeJustNow => '방금';

  @override
  String get noArchivedNotes => '보관한 노트가 아직 없습니다.';

  @override
  String get noMyNotes => '아직 노트가 없습니다.\n지도 탭에서 만들어 보세요.';

  @override
  String get profileTitle => '프로필';

  @override
  String get blockUserAction => '사용자 차단';

  @override
  String get unblockUserAction => '차단 해제';

  @override
  String blockUserTitle(String name) {
    return '$name님을 차단할까요?';
  }

  @override
  String get blockUserConfirmation =>
      '이 사용자의 노트와 메시지가 숨겨집니다. 서로의 팔로우가 해제되고, 내가 소유한 노트에 대한 접근 권한도 삭제됩니다. 다른 사람이 소유한 노트에서는 계속 마주칠 수 있습니다.';

  @override
  String get blockUserConfirmAction => '차단';

  @override
  String unblockUserTitle(String name) {
    return '$name님의 차단을 해제할까요?';
  }

  @override
  String get unblockUserConfirmation =>
      '이 사용자의 콘텐츠가 다시 표시될 수 있습니다. 이전 팔로우와 내 노트에 대한 접근 권한은 복원되지 않습니다.';

  @override
  String userBlocked(String name) {
    return '$name님을 차단했습니다.';
  }

  @override
  String userUnblocked(String name) {
    return '$name님의 차단을 해제했습니다.';
  }

  @override
  String updateUserBlockFailed(Object error) {
    return '차단 설정을 변경하지 못했습니다: $error';
  }

  @override
  String get settingsTitle => '설정';

  @override
  String get blockedUsersTitle => '차단한 사용자';

  @override
  String get blockedUsersDescription => '차단한 사용자를 확인하거나 차단 해제';

  @override
  String get noBlockedUsers => '차단한 사용자가 없습니다.';

  @override
  String blockedUsersLoadFailed(Object error) {
    return '차단한 사용자를 불러오지 못했습니다: $error';
  }

  @override
  String get settingsLanguageTitle => '앱 언어';

  @override
  String get settingsLanguageSystem => '자동(시스템)';

  @override
  String get settingsLanguageSystemDescription => '기기의 언어 설정을 사용합니다';

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
      '이 기기의 표시 언어는 변경되었지만 계정에 저장하지 못했습니다.';

  @override
  String get settingsMapStyleTitle => '지도 스타일';

  @override
  String get settingsMapStyleAuto => '자동';

  @override
  String get settingsMapStyleStandard => '표준';

  @override
  String get settingsMapStyleLight => '라이트';

  @override
  String get settingsMapStyleDark => '다크';

  @override
  String get settingsMapStylePop => '팝';

  @override
  String get settingsMapStyleAutoDescription => '시스템 화면 모드를 따릅니다';

  @override
  String get settingsMapStyleStandardDescription => '깔끔하고 간결한 표시';

  @override
  String get settingsMapStyleLightDescription => 'Apple 지도를 라이트 모드로 사용합니다';

  @override
  String get settingsMapStyleDarkDescription => '밤에도 보기 편한 어두운 표시';

  @override
  String get settingsMapStylePopDescription => '밝고 화려한 표시';

  @override
  String get settingsNotificationsTitle => '알림';

  @override
  String get notificationsMaintainedNotesTitle => '관리 중인 노트';

  @override
  String get notificationsMaintainedNotesDescription =>
      '관리하는 노트에 새 메시지가 오면 알림을 받습니다.';

  @override
  String get notificationsTurnOnTooltip => '관리 중인 노트 알림 켜기';

  @override
  String get notificationsTurnOffTooltip => '관리 중인 노트 알림 끄기';

  @override
  String get notificationsPermissionDenied =>
      '알림이 허용되지 않았습니다. 새 메시지 알림을 받으려면 시스템 설정에서 알림을 켜 주세요.';

  @override
  String get notificationsEnableFailed => '관리 중인 노트 알림을 켜지 못했습니다.';

  @override
  String get notificationsDisableFailed => '관리 중인 노트 알림을 끄지 못했습니다.';

  @override
  String get notificationPreviewsTitle => '메시지 미리보기';

  @override
  String get notificationPreviewsDescription => '관리 중인 노트 알림에 메시지 내용을 표시합니다.';

  @override
  String get notificationPreviewsUpdateFailed => '알림 미리보기를 업데이트하지 못했습니다.';

  @override
  String get editNickname => '닉네임 편집';

  @override
  String get nicknameLabel => '닉네임';

  @override
  String get nicknameUpdated => '닉네임을 변경했습니다.';

  @override
  String nicknameUpdateFailed(Object error) {
    return '닉네임을 변경하지 못했습니다: $error';
  }

  @override
  String get manageSubscription => '구독 관리';

  @override
  String get upgradeToPro => 'PRO로 업그레이드';

  @override
  String get proBenefitsSummary => '광고 제거, 노트 200개 보관 및 PRO 기능 이용';

  @override
  String get subscriptionManagementSummary => '결제, 취소 및 지원';

  @override
  String get proHeroTitle => '모든 장소를 특별한 기억으로';

  @override
  String get proHeroSubtitle => '세계 곳곳에 노트를 남기고, 다시 보고, 공유하는 더 많은 방법을 만나 보세요.';

  @override
  String get proFeatureAdFree => '광고 없이 세계 일기 즐기기';

  @override
  String proFeatureNoteLimit(int count) {
    return '활성 노트를 최대 $count개까지 보관';
  }

  @override
  String get proFeatureAccessArea => '더 넓은 범위에서 주변 노트 열기';

  @override
  String proMonthlyPlan(String price) {
    return '월 $price';
  }

  @override
  String proYearlyPlan(String price) {
    return '연 $price';
  }

  @override
  String proIntroOffer(String price) {
    return '첫해 $price';
  }

  @override
  String get proChoosePlan => 'PRO 요금제 선택';

  @override
  String get moderation => '콘텐츠 관리';

  @override
  String get signOut => '로그아웃';

  @override
  String get homeWorldSelectionTitle => '홈 월드 선택';

  @override
  String get homeWorldSelectionIntro => '홈 월드는 계정 데이터를 가까운 지역에 보관합니다.';

  @override
  String get homeWorldSelectionPermanentWarning =>
      '이 선택은 나중에 변경할 수 없습니다. 홈을 옮기지 않고도 준비된 다른 월드를 방문할 수 있습니다.';

  @override
  String get homeWorldSelectionUnavailable => '현재 선택할 수 있는 홈 월드가 없습니다.';

  @override
  String get homeWorldSelectionLoadFailed => '계정 준비 상태를 불러오지 못했습니다.';

  @override
  String get homeWorldSelectionSubmitFailed => '홈 월드를 설정하지 못했습니다. 다시 시도해 주세요.';

  @override
  String get homeWorldSelectionConfirm => '영구 홈으로 설정';

  @override
  String get worldAsia => '아시아';

  @override
  String get worldAsiaLocation => '일본 도쿄';

  @override
  String get worldNorthAmerica => '북미';

  @override
  String get worldNorthAmericaLocation => '미국 아이오와';

  @override
  String get worldEurope => '유럽';

  @override
  String get worldEuropeLocation => '벨기에';

  @override
  String get followers => '팔로워';

  @override
  String get following => '팔로잉';

  @override
  String subscriptionUnavailableBuild(String planName) {
    return '이 빌드에서는 $planName을(를) 사용할 수 없습니다.';
  }

  @override
  String subscriptionTemporarilyUnavailable(String planName) {
    return '$planName을(를) 일시적으로 사용할 수 없습니다.';
  }
}
