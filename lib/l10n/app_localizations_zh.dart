// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appName => '世界日记';

  @override
  String get commonCancel => '取消';

  @override
  String get commonSave => '保存';

  @override
  String get commonRetry => '重试';

  @override
  String get commonTryAgain => '再试一次';

  @override
  String commonError(Object error) {
    return '错误：$error';
  }

  @override
  String get navMap => '地图';

  @override
  String get navNotes => '笔记';

  @override
  String get navNotifications => '通知';

  @override
  String get navProfile => '个人资料';

  @override
  String get locationPermissionTitle => '需要位置权限';

  @override
  String get locationPermissionMessage => '请允许定位，以完整体验世界日记。';

  @override
  String get locationPermissionOpenSettings => '打开设置';

  @override
  String get locationPermissionAllow => '允许定位';

  @override
  String get locationServiceDisabledTitle => '请开启定位服务';

  @override
  String get locationServiceDisabledMessage => '请开启定位服务以使用世界日记。';

  @override
  String get locationServiceOpenSettings => '打开定位设置';

  @override
  String get locationSearching => '正在获取你的位置…';

  @override
  String get locationUnavailable => '无法获取位置。';

  @override
  String get locationUnavailableHelp => '请在设置中允许位置访问，\n或移动到 GPS 信号更好的地方。';

  @override
  String get locationLoadFailed => '无法加载位置。';

  @override
  String get currentLocationUnavailable => '无法获取你当前的位置。';

  @override
  String get enableLocation => '启用定位';

  @override
  String get enableLocationSettingsTooltip => '打开设置以启用定位';

  @override
  String get enableLocationPermissionTooltip => '允许定位以添加笔记';

  @override
  String get enableLocationServiceTooltip => '打开定位设置';

  @override
  String get mapNotesTitle => '附近的笔记';

  @override
  String get mapAddNote => '添加笔记';

  @override
  String get mapList => '列表';

  @override
  String get mapRefreshNotes => '刷新地图笔记';

  @override
  String mapHideAccessArea(String radius) {
    return '隐藏 $radius 访问范围';
  }

  @override
  String mapShowAccessArea(String radius) {
    return '显示 $radius 访问范围';
  }

  @override
  String get mapLoadingNotes => '正在加载附近的笔记…';

  @override
  String get mapNoNotes => '这个区域还没有笔记。\n移动地图或在这里留下一则吧！';

  @override
  String mapDistanceMeters(int distance) {
    return '距离 $distance 米';
  }

  @override
  String mapDistanceKilometers(String distance) {
    return '距离 $distance 公里';
  }

  @override
  String get mapFromFollowing => '来自你关注的人';

  @override
  String get mapNewFromFollowing => '你关注的人有新笔记';

  @override
  String get mapFromFollowingSemantic => '这是你关注的作者创建的笔记。';

  @override
  String get newMessages => '新消息';

  @override
  String createdAt(String date) {
    return '创建时间 $date';
  }

  @override
  String expiresAt(String date) {
    return '到期时间 $date';
  }

  @override
  String get noteClosed => '已关闭';

  @override
  String get notePrivate => '私密';

  @override
  String get noteWithinRange => '你在访问范围内，可以打开这则笔记。';

  @override
  String get noteOutsideRange => '你在访问范围外，请靠近后再打开。';

  @override
  String get noteOpenNow => '立即打开';

  @override
  String get noteMoveCloser => '靠近后打开';

  @override
  String messageCount(int count) {
    return '$count 条消息';
  }

  @override
  String likeCount(int count) {
    return '$count 个赞';
  }

  @override
  String footprintCount(int count) {
    return '$count 次足迹';
  }

  @override
  String get footprintsOn => '足迹记录已开启';

  @override
  String get footprintsOff => '足迹记录已关闭';

  @override
  String get noteOpening => '正在打开…';

  @override
  String get noteView => '查看笔记';

  @override
  String get noteOpen => '打开笔记';

  @override
  String get noteAvailableNearby => '靠近后即可打开';

  @override
  String get noteExpired => '已到期';

  @override
  String noteExpiresMonths(int count) {
    return '$count 个月后到期';
  }

  @override
  String noteExpiresDays(int count) {
    return '$count 天后到期';
  }

  @override
  String noteExpiresHours(int count) {
    return '$count 小时后到期';
  }

  @override
  String get noteExpiresSoon => '即将到期';

  @override
  String get goPro => '升级 PRO';

  @override
  String get threadOptions => '笔记选项';

  @override
  String get writeMessage => '写消息';

  @override
  String get likeNote => '为笔记点赞';

  @override
  String get unlikeNote => '取消笔记点赞';

  @override
  String get cannotLikeOwnNote => '无法为自己的笔记点赞';

  @override
  String get likeUnavailable => '目前无法点赞';

  @override
  String get noMessages => '还没有消息。\n来写下第一条吧！';

  @override
  String get youLabel => '你';

  @override
  String get messageSending => '发送中…';

  @override
  String messageScheduledAt(String time) {
    return '计划于 $time 发布';
  }

  @override
  String sortNotesTooltip(String sort) {
    return '排序笔记：$sort';
  }

  @override
  String sortNotesSelected(String sort) {
    return '排序笔记，已选择 $sort';
  }

  @override
  String sortedBy(String sort) {
    return '排序方式：$sort';
  }

  @override
  String get sortDistance => '距离';

  @override
  String get sortLastActivity => '最近活动';

  @override
  String get sortNewest => '最新创建';

  @override
  String get sortExpiresSoon => '即将到期';

  @override
  String get sortMostLiked => '最多赞';

  @override
  String get sortArchivedNewest => '最近归档';

  @override
  String get sortArchivedOldest => '最早归档';

  @override
  String get myNotesTitle => '笔记';

  @override
  String get myNotesTab => '我的笔记';

  @override
  String get archivedNotesTab => '归档';

  @override
  String get archiveNoteTitle => '要归档这则笔记吗？';

  @override
  String get archiveNoteMessage =>
      '笔记将从地图上消失、变为只读，并释放一个笔记名额。归档后无法恢复，但以后可以沿用标题、说明和位置创建新笔记。';

  @override
  String get archiveAction => '归档';

  @override
  String archiveFailed(Object error) {
    return '无法归档笔记：$error';
  }

  @override
  String get loadMore => '加载更多';

  @override
  String get retryLoadMore => '重新加载更多内容';

  @override
  String get createdNotes => '创建的笔记';

  @override
  String get archivedNotes => '归档的笔记';

  @override
  String lastActive(String time) {
    return '最后活动 $time';
  }

  @override
  String archivedAt(String time) {
    return '归档于 $time';
  }

  @override
  String get createFromArchiveTooltip => '从归档内容创建新笔记';

  @override
  String get archiveNoteTooltip => '归档笔记';

  @override
  String relativeDaysAgo(int count) {
    return '$count 天前';
  }

  @override
  String relativeHoursAgo(int count) {
    return '$count 小时前';
  }

  @override
  String relativeMinutesAgo(int count) {
    return '$count 分钟前';
  }

  @override
  String get relativeJustNow => '刚刚';

  @override
  String get noArchivedNotes => '还没有归档的笔记。';

  @override
  String get noMyNotes => '还没有笔记。\n请从地图标签页创建一则。';

  @override
  String get profileTitle => '个人资料';

  @override
  String get settingsTitle => '设置';

  @override
  String get editNickname => '编辑昵称';

  @override
  String get nicknameLabel => '昵称';

  @override
  String get nicknameUpdated => '昵称已更新。';

  @override
  String nicknameUpdateFailed(Object error) {
    return '无法更新昵称：$error';
  }

  @override
  String get manageSubscription => '管理订阅';

  @override
  String get upgradeToPro => '升级至 PRO';

  @override
  String get proBenefitsSummary => '移除广告、保留 200 则笔记并解锁 PRO 功能';

  @override
  String get subscriptionManagementSummary => '付款、取消与支持';

  @override
  String get proHeroTitle => '让每个地方都值得记住';

  @override
  String get proHeroSubtitle => '解锁更多方式，在世界各地留下、重温并分享笔记。';

  @override
  String get proFeatureAdFree => '无广告畅享世界日记';

  @override
  String proFeatureNoteLimit(int count) {
    return '最多保留 $count 则使用中的笔记';
  }

  @override
  String get proFeatureAccessArea => '从更大的范围打开附近笔记';

  @override
  String proMonthlyPlan(String price) {
    return '每月 $price';
  }

  @override
  String proYearlyPlan(String price) {
    return '每年 $price';
  }

  @override
  String proIntroOffer(String price) {
    return '首年 $price';
  }

  @override
  String get proChoosePlan => '选择 PRO 方案';

  @override
  String get moderation => '内容管理';

  @override
  String get signOut => '退出登录';

  @override
  String get followers => '粉丝';

  @override
  String get following => '关注中';

  @override
  String subscriptionUnavailableBuild(String planName) {
    return '此版本无法使用 $planName。';
  }

  @override
  String subscriptionTemporarilyUnavailable(String planName) {
    return '$planName 目前暂时无法使用。';
  }
}

/// The translations for Chinese, using the Han script (`zh_Hans`).
class AppLocalizationsZhHans extends AppLocalizationsZh {
  AppLocalizationsZhHans() : super('zh_Hans');

  @override
  String get appName => '世界日记';

  @override
  String get commonCancel => '取消';

  @override
  String get commonSave => '保存';

  @override
  String get commonRetry => '重试';

  @override
  String get commonTryAgain => '再试一次';

  @override
  String commonError(Object error) {
    return '错误：$error';
  }

  @override
  String get navMap => '地图';

  @override
  String get navNotes => '笔记';

  @override
  String get navNotifications => '通知';

  @override
  String get navProfile => '个人资料';

  @override
  String get locationPermissionTitle => '需要位置权限';

  @override
  String get locationPermissionMessage => '请允许定位，以完整体验世界日记。';

  @override
  String get locationPermissionOpenSettings => '打开设置';

  @override
  String get locationPermissionAllow => '允许定位';

  @override
  String get locationServiceDisabledTitle => '请开启定位服务';

  @override
  String get locationServiceDisabledMessage => '请开启定位服务以使用世界日记。';

  @override
  String get locationServiceOpenSettings => '打开定位设置';

  @override
  String get locationSearching => '正在获取你的位置…';

  @override
  String get locationUnavailable => '无法获取位置。';

  @override
  String get locationUnavailableHelp => '请在设置中允许位置访问，\n或移动到 GPS 信号更好的地方。';

  @override
  String get locationLoadFailed => '无法加载位置。';

  @override
  String get currentLocationUnavailable => '无法获取你当前的位置。';

  @override
  String get enableLocation => '启用定位';

  @override
  String get enableLocationSettingsTooltip => '打开设置以启用定位';

  @override
  String get enableLocationPermissionTooltip => '允许定位以添加笔记';

  @override
  String get enableLocationServiceTooltip => '打开定位设置';

  @override
  String get mapNotesTitle => '附近的笔记';

  @override
  String get mapAddNote => '添加笔记';

  @override
  String get mapList => '列表';

  @override
  String get mapRefreshNotes => '刷新地图笔记';

  @override
  String mapHideAccessArea(String radius) {
    return '隐藏 $radius 访问范围';
  }

  @override
  String mapShowAccessArea(String radius) {
    return '显示 $radius 访问范围';
  }

  @override
  String get mapLoadingNotes => '正在加载附近的笔记…';

  @override
  String get mapNoNotes => '这个区域还没有笔记。\n移动地图或在这里留下一则吧！';

  @override
  String mapDistanceMeters(int distance) {
    return '距离 $distance 米';
  }

  @override
  String mapDistanceKilometers(String distance) {
    return '距离 $distance 公里';
  }

  @override
  String get mapFromFollowing => '来自你关注的人';

  @override
  String get mapNewFromFollowing => '你关注的人有新笔记';

  @override
  String get mapFromFollowingSemantic => '这是你关注的作者创建的笔记。';

  @override
  String get newMessages => '新消息';

  @override
  String createdAt(String date) {
    return '创建时间 $date';
  }

  @override
  String expiresAt(String date) {
    return '到期时间 $date';
  }

  @override
  String get noteClosed => '已关闭';

  @override
  String get notePrivate => '私密';

  @override
  String get noteWithinRange => '你在访问范围内，可以打开这则笔记。';

  @override
  String get noteOutsideRange => '你在访问范围外，请靠近后再打开。';

  @override
  String get noteOpenNow => '立即打开';

  @override
  String get noteMoveCloser => '靠近后打开';

  @override
  String messageCount(int count) {
    return '$count 条消息';
  }

  @override
  String likeCount(int count) {
    return '$count 个赞';
  }

  @override
  String footprintCount(int count) {
    return '$count 次足迹';
  }

  @override
  String get footprintsOn => '足迹记录已开启';

  @override
  String get footprintsOff => '足迹记录已关闭';

  @override
  String get noteOpening => '正在打开…';

  @override
  String get noteView => '查看笔记';

  @override
  String get noteOpen => '打开笔记';

  @override
  String get noteAvailableNearby => '靠近后即可打开';

  @override
  String get noteExpired => '已到期';

  @override
  String noteExpiresMonths(int count) {
    return '$count 个月后到期';
  }

  @override
  String noteExpiresDays(int count) {
    return '$count 天后到期';
  }

  @override
  String noteExpiresHours(int count) {
    return '$count 小时后到期';
  }

  @override
  String get noteExpiresSoon => '即将到期';

  @override
  String get goPro => '升级 PRO';

  @override
  String get threadOptions => '笔记选项';

  @override
  String get writeMessage => '写消息';

  @override
  String get likeNote => '为笔记点赞';

  @override
  String get unlikeNote => '取消笔记点赞';

  @override
  String get cannotLikeOwnNote => '无法为自己的笔记点赞';

  @override
  String get likeUnavailable => '目前无法点赞';

  @override
  String get noMessages => '还没有消息。\n来写下第一条吧！';

  @override
  String get youLabel => '你';

  @override
  String get messageSending => '发送中…';

  @override
  String messageScheduledAt(String time) {
    return '计划于 $time 发布';
  }

  @override
  String sortNotesTooltip(String sort) {
    return '排序笔记：$sort';
  }

  @override
  String sortNotesSelected(String sort) {
    return '排序笔记，已选择 $sort';
  }

  @override
  String sortedBy(String sort) {
    return '排序方式：$sort';
  }

  @override
  String get sortDistance => '距离';

  @override
  String get sortLastActivity => '最近活动';

  @override
  String get sortNewest => '最新创建';

  @override
  String get sortExpiresSoon => '即将到期';

  @override
  String get sortMostLiked => '最多赞';

  @override
  String get sortArchivedNewest => '最近归档';

  @override
  String get sortArchivedOldest => '最早归档';

  @override
  String get myNotesTitle => '笔记';

  @override
  String get myNotesTab => '我的笔记';

  @override
  String get archivedNotesTab => '归档';

  @override
  String get archiveNoteTitle => '要归档这则笔记吗？';

  @override
  String get archiveNoteMessage =>
      '笔记将从地图上消失、变为只读，并释放一个笔记名额。归档后无法恢复，但以后可以沿用标题、说明和位置创建新笔记。';

  @override
  String get archiveAction => '归档';

  @override
  String archiveFailed(Object error) {
    return '无法归档笔记：$error';
  }

  @override
  String get loadMore => '加载更多';

  @override
  String get retryLoadMore => '重新加载更多内容';

  @override
  String get createdNotes => '创建的笔记';

  @override
  String get archivedNotes => '归档的笔记';

  @override
  String lastActive(String time) {
    return '最后活动 $time';
  }

  @override
  String archivedAt(String time) {
    return '归档于 $time';
  }

  @override
  String get createFromArchiveTooltip => '从归档内容创建新笔记';

  @override
  String get archiveNoteTooltip => '归档笔记';

  @override
  String relativeDaysAgo(int count) {
    return '$count 天前';
  }

  @override
  String relativeHoursAgo(int count) {
    return '$count 小时前';
  }

  @override
  String relativeMinutesAgo(int count) {
    return '$count 分钟前';
  }

  @override
  String get relativeJustNow => '刚刚';

  @override
  String get noArchivedNotes => '还没有归档的笔记。';

  @override
  String get noMyNotes => '还没有笔记。\n请从地图标签页创建一则。';

  @override
  String get profileTitle => '个人资料';

  @override
  String get settingsTitle => '设置';

  @override
  String get editNickname => '编辑昵称';

  @override
  String get nicknameLabel => '昵称';

  @override
  String get nicknameUpdated => '昵称已更新。';

  @override
  String nicknameUpdateFailed(Object error) {
    return '无法更新昵称：$error';
  }

  @override
  String get manageSubscription => '管理订阅';

  @override
  String get upgradeToPro => '升级至 PRO';

  @override
  String get proBenefitsSummary => '移除广告、保留 200 则笔记并解锁 PRO 功能';

  @override
  String get subscriptionManagementSummary => '付款、取消与支持';

  @override
  String get proHeroTitle => '让每个地方都值得记住';

  @override
  String get proHeroSubtitle => '解锁更多方式，在世界各地留下、重温并分享笔记。';

  @override
  String get proFeatureAdFree => '无广告畅享世界日记';

  @override
  String proFeatureNoteLimit(int count) {
    return '最多保留 $count 则使用中的笔记';
  }

  @override
  String get proFeatureAccessArea => '从更大的范围打开附近笔记';

  @override
  String proMonthlyPlan(String price) {
    return '每月 $price';
  }

  @override
  String proYearlyPlan(String price) {
    return '每年 $price';
  }

  @override
  String proIntroOffer(String price) {
    return '首年 $price';
  }

  @override
  String get proChoosePlan => '选择 PRO 方案';

  @override
  String get moderation => '内容管理';

  @override
  String get signOut => '退出登录';

  @override
  String get followers => '粉丝';

  @override
  String get following => '关注中';

  @override
  String subscriptionUnavailableBuild(String planName) {
    return '此版本无法使用 $planName。';
  }

  @override
  String subscriptionTemporarilyUnavailable(String planName) {
    return '$planName 目前暂时无法使用。';
  }
}

/// The translations for Chinese, using the Han script (`zh_Hant`).
class AppLocalizationsZhHant extends AppLocalizationsZh {
  AppLocalizationsZhHant() : super('zh_Hant');

  @override
  String get appName => '世界日記';

  @override
  String get commonCancel => '取消';

  @override
  String get commonSave => '儲存';

  @override
  String get commonRetry => '重試';

  @override
  String get commonTryAgain => '再試一次';

  @override
  String commonError(Object error) {
    return '錯誤：$error';
  }

  @override
  String get navMap => '地圖';

  @override
  String get navNotes => '筆記';

  @override
  String get navNotifications => '通知';

  @override
  String get navProfile => '個人檔案';

  @override
  String get locationPermissionTitle => '需要位置權限';

  @override
  String get locationPermissionMessage => '請允許定位，以完整體驗世界日記。';

  @override
  String get locationPermissionOpenSettings => '開啟設定';

  @override
  String get locationPermissionAllow => '允許定位';

  @override
  String get locationServiceDisabledTitle => '請開啟定位服務';

  @override
  String get locationServiceDisabledMessage => '請開啟定位服務以使用世界日記。';

  @override
  String get locationServiceOpenSettings => '開啟定位設定';

  @override
  String get locationSearching => '正在取得你的位置…';

  @override
  String get locationUnavailable => '無法取得位置。';

  @override
  String get locationUnavailableHelp => '請在設定中允許位置存取，\n或移動到 GPS 訊號較佳的地方。';

  @override
  String get locationLoadFailed => '無法載入位置。';

  @override
  String get currentLocationUnavailable => '無法取得你目前的位置。';

  @override
  String get enableLocation => '啟用定位';

  @override
  String get enableLocationSettingsTooltip => '開啟設定以啟用定位';

  @override
  String get enableLocationPermissionTooltip => '允許定位以新增筆記';

  @override
  String get enableLocationServiceTooltip => '開啟定位設定';

  @override
  String get mapNotesTitle => '附近的筆記';

  @override
  String get mapAddNote => '新增筆記';

  @override
  String get mapList => '列表';

  @override
  String get mapRefreshNotes => '重新整理地圖筆記';

  @override
  String mapHideAccessArea(String radius) {
    return '隱藏 $radius 存取範圍';
  }

  @override
  String mapShowAccessArea(String radius) {
    return '顯示 $radius 存取範圍';
  }

  @override
  String get mapLoadingNotes => '正在載入附近的筆記…';

  @override
  String get mapNoNotes => '這個區域還沒有筆記。\n移動地圖或在這裡留下一則吧！';

  @override
  String mapDistanceMeters(int distance) {
    return '距離 $distance 公尺';
  }

  @override
  String mapDistanceKilometers(String distance) {
    return '距離 $distance 公里';
  }

  @override
  String get mapFromFollowing => '來自你追蹤的人';

  @override
  String get mapNewFromFollowing => '你追蹤的人有新筆記';

  @override
  String get mapFromFollowingSemantic => '這是你追蹤的作者所建立的筆記。';

  @override
  String get newMessages => '新訊息';

  @override
  String createdAt(String date) {
    return '建立時間 $date';
  }

  @override
  String expiresAt(String date) {
    return '到期時間 $date';
  }

  @override
  String get noteClosed => '已關閉';

  @override
  String get notePrivate => '私人';

  @override
  String get noteWithinRange => '你位於存取範圍內，可以開啟這則筆記。';

  @override
  String get noteOutsideRange => '你位於存取範圍外，請靠近後再開啟。';

  @override
  String get noteOpenNow => '立即開啟';

  @override
  String get noteMoveCloser => '靠近後開啟';

  @override
  String messageCount(int count) {
    return '$count 則訊息';
  }

  @override
  String likeCount(int count) {
    return '$count 個讚';
  }

  @override
  String footprintCount(int count) {
    return '$count 次足跡';
  }

  @override
  String get footprintsOn => '足跡記錄已開啟';

  @override
  String get footprintsOff => '足跡記錄已關閉';

  @override
  String get noteOpening => '正在開啟…';

  @override
  String get noteView => '查看筆記';

  @override
  String get noteOpen => '開啟筆記';

  @override
  String get noteAvailableNearby => '靠近後即可開啟';

  @override
  String get noteExpired => '已到期';

  @override
  String noteExpiresMonths(int count) {
    return '$count 個月後到期';
  }

  @override
  String noteExpiresDays(int count) {
    return '$count 天後到期';
  }

  @override
  String noteExpiresHours(int count) {
    return '$count 小時後到期';
  }

  @override
  String get noteExpiresSoon => '即將到期';

  @override
  String get goPro => '升級 PRO';

  @override
  String get threadOptions => '筆記選項';

  @override
  String get writeMessage => '撰寫訊息';

  @override
  String get likeNote => '為筆記按讚';

  @override
  String get unlikeNote => '取消筆記讚';

  @override
  String get cannotLikeOwnNote => '無法為自己的筆記按讚';

  @override
  String get likeUnavailable => '目前無法按讚';

  @override
  String get noMessages => '還沒有訊息。\n來寫下第一則吧！';

  @override
  String get youLabel => '你';

  @override
  String get messageSending => '傳送中…';

  @override
  String messageScheduledAt(String time) {
    return '預定於 $time 發佈';
  }

  @override
  String sortNotesTooltip(String sort) {
    return '排序筆記：$sort';
  }

  @override
  String sortNotesSelected(String sort) {
    return '排序筆記，已選擇 $sort';
  }

  @override
  String sortedBy(String sort) {
    return '排序方式：$sort';
  }

  @override
  String get sortDistance => '距離';

  @override
  String get sortLastActivity => '最近活動';

  @override
  String get sortNewest => '最新建立';

  @override
  String get sortExpiresSoon => '即將到期';

  @override
  String get sortMostLiked => '最多讚';

  @override
  String get sortArchivedNewest => '最近封存';

  @override
  String get sortArchivedOldest => '最早封存';

  @override
  String get myNotesTitle => '筆記';

  @override
  String get myNotesTab => '我的筆記';

  @override
  String get archivedNotesTab => '封存';

  @override
  String get archiveNoteTitle => '要封存這則筆記嗎？';

  @override
  String get archiveNoteMessage =>
      '筆記將從地圖上消失、變為唯讀，並釋出一個筆記名額。封存後無法復原，但日後可沿用標題、說明和位置建立新筆記。';

  @override
  String get archiveAction => '封存';

  @override
  String archiveFailed(Object error) {
    return '無法封存筆記：$error';
  }

  @override
  String get loadMore => '載入更多';

  @override
  String get retryLoadMore => '重新載入更多內容';

  @override
  String get createdNotes => '建立的筆記';

  @override
  String get archivedNotes => '封存的筆記';

  @override
  String lastActive(String time) {
    return '最後活動 $time';
  }

  @override
  String archivedAt(String time) {
    return '封存於 $time';
  }

  @override
  String get createFromArchiveTooltip => '從封存內容建立新筆記';

  @override
  String get archiveNoteTooltip => '封存筆記';

  @override
  String relativeDaysAgo(int count) {
    return '$count 天前';
  }

  @override
  String relativeHoursAgo(int count) {
    return '$count 小時前';
  }

  @override
  String relativeMinutesAgo(int count) {
    return '$count 分鐘前';
  }

  @override
  String get relativeJustNow => '剛剛';

  @override
  String get noArchivedNotes => '還沒有封存的筆記。';

  @override
  String get noMyNotes => '還沒有筆記。\n請從地圖分頁建立一則。';

  @override
  String get profileTitle => '個人檔案';

  @override
  String get settingsTitle => '設定';

  @override
  String get editNickname => '編輯暱稱';

  @override
  String get nicknameLabel => '暱稱';

  @override
  String get nicknameUpdated => '暱稱已更新。';

  @override
  String nicknameUpdateFailed(Object error) {
    return '無法更新暱稱：$error';
  }

  @override
  String get manageSubscription => '管理訂閱';

  @override
  String get upgradeToPro => '升級至 PRO';

  @override
  String get proBenefitsSummary => '移除廣告、保留 200 則筆記並解鎖 PRO 功能';

  @override
  String get subscriptionManagementSummary => '付款、取消與支援';

  @override
  String get proHeroTitle => '讓每個地方都值得記住';

  @override
  String get proHeroSubtitle => '解鎖更多方式，在世界各地留下、重溫並分享筆記。';

  @override
  String get proFeatureAdFree => '無廣告享受世界日記';

  @override
  String proFeatureNoteLimit(int count) {
    return '最多保留 $count 則使用中的筆記';
  }

  @override
  String get proFeatureAccessArea => '從更大的範圍開啟附近筆記';

  @override
  String proMonthlyPlan(String price) {
    return '每月 $price';
  }

  @override
  String proYearlyPlan(String price) {
    return '每年 $price';
  }

  @override
  String proIntroOffer(String price) {
    return '首年 $price';
  }

  @override
  String get proChoosePlan => '選擇 PRO 方案';

  @override
  String get moderation => '內容管理';

  @override
  String get signOut => '登出';

  @override
  String get followers => '粉絲';

  @override
  String get following => '追蹤中';

  @override
  String subscriptionUnavailableBuild(String planName) {
    return '此版本無法使用 $planName。';
  }

  @override
  String subscriptionTemporarilyUnavailable(String planName) {
    return '$planName 目前暫時無法使用。';
  }
}
