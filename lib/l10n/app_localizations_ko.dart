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
  String get youLabel => '나';

  @override
  String get messageSending => '전송 중…';

  @override
  String messageScheduledAt(String time) {
    return '$time에 게시 예정';
  }

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
  String get settingsTitle => '설정';

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
  String get settingsDataRegionTitle => '데이터 지역';

  @override
  String get settingsDataRegionDescription =>
      '요청을 처리할 지역을 선택합니다. 자동은 현재 위치에서 가장 가까운 지역을 선택하며 여행 중에는 직접 변경할 수 있습니다.';

  @override
  String get settingsDataRegionAuto => '자동(가장 가까운 지역)';

  @override
  String settingsDataRegionCurrent(String region) {
    return '현재: $region';
  }

  @override
  String get settingsRegionAsiaTokyo => '아시아(도쿄)';

  @override
  String get settingsRegionAmericasUsCentral => '아메리카(미국 중부)';

  @override
  String get settingsRegionEuropeBelgium => '유럽(벨기에)';

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
