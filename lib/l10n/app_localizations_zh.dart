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
  String get noNotifications => '暂无通知。';

  @override
  String get noFollowers => '暂无关注者。';

  @override
  String get noFollowing => '尚未关注任何人。';

  @override
  String get noFootprints => '暂无足迹。';

  @override
  String get noFootprintsDescription => '访客打开此笔记后会显示在这里。';

  @override
  String get noAccessMembers => '尚无人拥有访问权限。分享链接即可添加成员。';

  @override
  String get noModerationReviews => '暂无审核项目。';

  @override
  String get youLabel => '你';

  @override
  String get messageSending => '发送中…';

  @override
  String messageScheduledAt(String time) {
    return '计划于 $time 发布';
  }

  @override
  String get reportMessageAction => '举报消息';

  @override
  String get reportNoteAction => '举报笔记';

  @override
  String get reportMessageTitle => '举报消息';

  @override
  String get reportNoteTitle => '举报笔记';

  @override
  String get reportMessageQuestion => '为什么要举报这条消息？';

  @override
  String get reportNoteQuestion => '为什么要举报这篇笔记？';

  @override
  String get reportReasonSpam => '垃圾信息或广告';

  @override
  String get reportReasonHarassment => '骚扰或欺凌';

  @override
  String get reportReasonSexual => '成人或露骨内容';

  @override
  String get reportReasonIllegal => '违法内容';

  @override
  String get reportReasonOther => '其他';

  @override
  String get reportMessagePrivacy => '您的用户ID、消息ID、笔记ID和所选原因将提供给管理员审核。';

  @override
  String get reportNotePrivacy => '您的用户ID、笔记ID和所选原因将提供给管理员审核。';

  @override
  String get reportSubmitting => '正在提交...';

  @override
  String get reportSubmitAction => '提交举报';

  @override
  String get reportSubmitted => '举报已提交。感谢您帮助维护社区安全。';

  @override
  String get reportAlsoBlockUser => '同时屏蔽此用户';

  @override
  String get reportAlsoBlockUserDescription => '提交举报后，此用户的笔记和消息将被隐藏。';

  @override
  String get reportSubmittedBlockFailed => '举报已提交，但未能屏蔽该用户。';

  @override
  String reportFailed(Object error) {
    return '无法提交举报：$error';
  }

  @override
  String get reportCooldown => '请稍候片刻再提交举报。';

  @override
  String get reportUnavailable => '此内容已无法举报。';

  @override
  String get contentModerationUnavailable => '安全检查暂时不可用，请重试。';

  @override
  String get contentNotAllowed => '此内容无法发布，请修改后重试。';

  @override
  String get imageNotAllowed => '无法使用此图片，请选择其他图片。';

  @override
  String get noteCreatedPinImageUploadFailed => '笔记已创建，但无法上传图钉图片。';

  @override
  String get noteCreateNetworkError => '无法连接服务器。请检查网络连接后重试。';

  @override
  String get noteCreateAuthenticationRequired => '请重新登录以创建笔记。';

  @override
  String get noteCreateFailed => '无法创建笔记，请重试。';

  @override
  String get noteCreateUnexpectedError => '发生意外错误，请重试。';

  @override
  String get noteCreateTitle => '新建笔记';

  @override
  String get noteTitleLabel => '标题';

  @override
  String get noteTitleHint => '这是一个怎样的地方？';

  @override
  String get noteTitleRequired => '请输入标题';

  @override
  String get noteDescriptionOptionalLabel => '描述（可选）';

  @override
  String get noteDescriptionHint => '介绍一下这个地方…';

  @override
  String get noteThemeLabel => '笔记主题';

  @override
  String get noteThemeChangeTitle => '更改主题';

  @override
  String get noteThemeChangeDescription => '此更改会影响所有人看到的笔记外观。';

  @override
  String get pinColorLabel => '图钉颜色';

  @override
  String get pinStyleLabel => '图钉样式';

  @override
  String get pinImageLabel => '图钉图片';

  @override
  String get iconLabel => '图标';

  @override
  String get imageLabel => '图片';

  @override
  String get publishLabel => '发布';

  @override
  String get publishNow => '立即';

  @override
  String get publishLater => '稍后';

  @override
  String get publishLaterSchedule => '稍后发布';

  @override
  String get publishIn15Minutes => '15分钟后';

  @override
  String get publishIn30Minutes => '30分钟后';

  @override
  String get publishIn1Hour => '1小时后';

  @override
  String get publishIn3Hours => '3小时后';

  @override
  String get publishTomorrow => '明天';

  @override
  String get publishCustom => '自定义';

  @override
  String get autoCloseAfter => '自动关闭时间';

  @override
  String get autoCloseDescription => '超过此期限后将停止接收消息并归档笔记。';

  @override
  String get expiryOneWeek => '1周';

  @override
  String get expiryOneMonth => '1个月';

  @override
  String expiryMonths(int count) {
    return '$count个月';
  }

  @override
  String get expiryOneYear => '1年';

  @override
  String expiryDays(int count) {
    return '$count天';
  }

  @override
  String get noteAccessLabel => '访问权限';

  @override
  String get createNoteAction => '创建笔记';

  @override
  String get noteCapacityChecking => '正在检查可用笔记名额…';

  @override
  String get noteLimitReached => '已达到笔记上限';

  @override
  String premiumNoteLimitMessage(int count, int limit) {
    return '您正在使用$limit个有效笔记名额中的$count个。请归档一个笔记或等待其到期后再创建。';
  }

  @override
  String freeNoteLimitMessage(int limit, int proLimit) {
    return '免费账户最多可保留$limit个有效笔记。请归档一个笔记，或升级到PRO以使用最多$proLimit个。';
  }

  @override
  String get forkLocationNotice => '新笔记将沿用已归档笔记的位置。';

  @override
  String get noteCreateLocationPermissionRequired => '创建笔记需要位置权限。';

  @override
  String get noteCreateLocationPermissionDisabledMessage =>
      '位置权限已关闭。请打开系统设置并允许位置访问，以便创建笔记。';

  @override
  String get noteCreateLocationServiceDisabledMessage =>
      '位置服务已关闭。请将其打开，以便在当前位置创建笔记。';

  @override
  String get noteCreateLocationUnavailable => '无法获取当前位置，请重试。';

  @override
  String get imagePin => '图片图钉';

  @override
  String get imagePinReady => '图片图钉已就绪';

  @override
  String get pinImageEmptyDescription => '添加裁剪后的缩略图。未设置时将使用默认图钉。';

  @override
  String get pinImageReadyDescription => '将上传此缩略图。';

  @override
  String get chooseImage => '选择图片';

  @override
  String get changeImage => '更换图片';

  @override
  String get removeImage => '移除图片';

  @override
  String get passwordLabel => '密码';

  @override
  String get patternLabel => '图案';

  @override
  String get publicNote => '公开笔记';

  @override
  String get lockedNote => '已锁定笔记';

  @override
  String noteLockSummary(String type) {
    return '$type锁';
  }

  @override
  String noteLockSummaryWithHint(String type) {
    return '带提示的$type锁';
  }

  @override
  String get anyoneNearbyCanOpen => '附近的任何人都可以打开。';

  @override
  String get setLock => '设置锁';

  @override
  String get changeLock => '更改锁';

  @override
  String get removeLock => '移除锁';

  @override
  String get noteThemeStandard => '标准';

  @override
  String get noteThemeStandardDescription => '沉静而熟悉的World Notes标准外观。';

  @override
  String get noteThemeAurora => '极光';

  @override
  String get noteThemeAuroraDescription => '靛蓝与水蓝、紫罗兰光影交织。';

  @override
  String get noteThemeCitrus => '柑橘活力';

  @override
  String get noteThemeCitrusDescription => '温暖的珊瑚橙搭配青绿色点缀。';

  @override
  String get noteThemeBotanical => '植物园';

  @override
  String get noteThemeBotanicalDescription => '沉稳的翡翠色与叶绿色。';

  @override
  String get noteThemeNeon => '霓虹网格';

  @override
  String get noteThemeNeonDescription => '暗色中的青蓝与紫红霓虹。';

  @override
  String get noteThemeEditorial => '杂志';

  @override
  String get noteThemeEditorialDescription => '纸张般的中性色配以钴蓝点缀。';

  @override
  String get noteFallbackTitle => '笔记';

  @override
  String get noteUnavailableTitle => '此笔记当前不可用。';

  @override
  String get noteUnavailableMessage => '它可能尚未发布、已经过期，或无法再从当前位置访问。';

  @override
  String get noteOpenFailedTitle => '无法打开此笔记。';

  @override
  String get noteOpenFailedMessage => '请检查网络连接，并确认您仍在笔记附近。';

  @override
  String get noteReadOnlyFromMyNotes => '从“我的笔记”打开时为只读。';

  @override
  String get notePrivateTitle => '这是一则私密笔记';

  @override
  String get notePrivatePasswordDescription => '请输入密码以阅读和发布消息。';

  @override
  String get notePrivatePatternDescription => '请绘制图案以阅读和发布消息。';

  @override
  String get notePrivateDescription => '请解锁笔记以阅读和发布消息。';

  @override
  String get enterPassword => '输入密码';

  @override
  String get drawPattern => '绘制图案';

  @override
  String get unlockAction => '解锁';

  @override
  String noteLockHint(String hint) {
    return '提示：$hint';
  }

  @override
  String get noteScheduledReadOnly => '此笔记已预约发布，目前尚不接收消息。';

  @override
  String get noteArchivedReadOnly => '此笔记已归档，仅供阅读。';

  @override
  String threadMessageLimitReached(int count) {
    return '此讨论串已达到$count条消息的上限，现已关闭。';
  }

  @override
  String get threadFullClosed => '此讨论串已满并关闭。';

  @override
  String get threadMaintainerClosed => '管理员已关闭此讨论串，仅供阅读。';

  @override
  String get closeThreadAction => '关闭讨论串';

  @override
  String get reopenThreadAction => '重新打开讨论串';

  @override
  String get changeThemeAction => '更改主题';

  @override
  String get manageAccessAction => '管理访问权限';

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
  String get blockUserAction => '屏蔽用户';

  @override
  String get unblockUserAction => '取消屏蔽';

  @override
  String blockUserTitle(String name) {
    return '屏蔽$name？';
  }

  @override
  String get blockUserConfirmation =>
      '此用户的笔记和消息将被隐藏。你们会互相取消关注，且对方将失去访问你所拥有笔记的权限。在其他人拥有的笔记中，你们仍可能同时出现。';

  @override
  String get blockUserConfirmAction => '屏蔽';

  @override
  String unblockUserTitle(String name) {
    return '取消屏蔽$name？';
  }

  @override
  String get unblockUserConfirmation => '此用户的内容可能会重新显示。之前的关注关系以及对你笔记的访问权限不会恢复。';

  @override
  String userBlocked(String name) {
    return '已屏蔽$name。';
  }

  @override
  String userUnblocked(String name) {
    return '已取消屏蔽$name。';
  }

  @override
  String updateUserBlockFailed(Object error) {
    return '无法更新屏蔽设置：$error';
  }

  @override
  String get settingsTitle => '设置';

  @override
  String get blockedUsersTitle => '已屏蔽的用户';

  @override
  String get blockedUsersDescription => '查看或取消屏蔽用户';

  @override
  String get noBlockedUsers => '你尚未屏蔽任何用户。';

  @override
  String blockedUsersLoadFailed(Object error) {
    return '无法加载已屏蔽的用户：$error';
  }

  @override
  String get settingsLanguageTitle => '应用语言';

  @override
  String get settingsLanguageSystem => '自动（系统）';

  @override
  String get settingsLanguageSystemDescription => '使用设备的语言设置';

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
  String get settingsLanguageUpdateFailed => '此设备的显示语言已更改，但无法保存到你的账户。';

  @override
  String get settingsMapStyleTitle => '地图样式';

  @override
  String get settingsMapStyleAuto => '自动';

  @override
  String get settingsMapStyleStandard => '标准';

  @override
  String get settingsMapStyleLight => '浅色';

  @override
  String get settingsMapStyleDark => '深色';

  @override
  String get settingsMapStylePop => '鲜艳';

  @override
  String get settingsMapStyleAutoDescription => '跟随系统外观';

  @override
  String get settingsMapStyleStandardDescription => '简洁清晰的显示';

  @override
  String get settingsMapStyleLightDescription => '以浅色模式使用 Apple 地图';

  @override
  String get settingsMapStyleDarkDescription => '夜间更舒适的深色显示';

  @override
  String get settingsMapStylePopDescription => '明亮多彩的显示';

  @override
  String get settingsDataRegionTitle => '数据区域';

  @override
  String get settingsDataRegionDescription =>
      '选择处理请求的区域。自动会选择离当前位置最近的区域，旅行时也可手动更改。';

  @override
  String get settingsDataRegionAuto => '自动（最近）';

  @override
  String settingsDataRegionCurrent(String region) {
    return '当前：$region';
  }

  @override
  String get settingsRegionAsiaTokyo => '亚洲（东京）';

  @override
  String get settingsRegionAmericasUsCentral => '美洲（美国中部）';

  @override
  String get settingsRegionEuropeBelgium => '欧洲（比利时）';

  @override
  String get settingsNotificationsTitle => '通知';

  @override
  String get notificationsMaintainedNotesTitle => '管理中的笔记';

  @override
  String get notificationsMaintainedNotesDescription => '你管理的笔记收到新消息时通知你。';

  @override
  String get notificationsTurnOnTooltip => '开启管理中笔记的通知';

  @override
  String get notificationsTurnOffTooltip => '关闭管理中笔记的通知';

  @override
  String get notificationsPermissionDenied => '通知未获允许。请在系统设置中启用通知以接收新消息提醒。';

  @override
  String get notificationsEnableFailed => '无法开启管理中笔记的通知。';

  @override
  String get notificationsDisableFailed => '无法关闭管理中笔记的通知。';

  @override
  String get notificationPreviewsTitle => '消息预览';

  @override
  String get notificationPreviewsDescription => '在管理中笔记的通知里显示消息内容。';

  @override
  String get notificationPreviewsUpdateFailed => '无法更新通知预览。';

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
  String get noNotifications => '暂无通知。';

  @override
  String get noFollowers => '暂无关注者。';

  @override
  String get noFollowing => '尚未关注任何人。';

  @override
  String get noFootprints => '暂无足迹。';

  @override
  String get noFootprintsDescription => '访客打开此笔记后会显示在这里。';

  @override
  String get noAccessMembers => '尚无人拥有访问权限。分享链接即可添加成员。';

  @override
  String get noModerationReviews => '暂无审核项目。';

  @override
  String get youLabel => '你';

  @override
  String get messageSending => '发送中…';

  @override
  String messageScheduledAt(String time) {
    return '计划于 $time 发布';
  }

  @override
  String get reportMessageAction => '举报消息';

  @override
  String get reportNoteAction => '举报笔记';

  @override
  String get reportMessageTitle => '举报消息';

  @override
  String get reportNoteTitle => '举报笔记';

  @override
  String get reportMessageQuestion => '为什么要举报这条消息？';

  @override
  String get reportNoteQuestion => '为什么要举报这篇笔记？';

  @override
  String get reportReasonSpam => '垃圾信息或广告';

  @override
  String get reportReasonHarassment => '骚扰或欺凌';

  @override
  String get reportReasonSexual => '成人或露骨内容';

  @override
  String get reportReasonIllegal => '违法内容';

  @override
  String get reportReasonOther => '其他';

  @override
  String get reportMessagePrivacy => '您的用户ID、消息ID、笔记ID和所选原因将提供给管理员审核。';

  @override
  String get reportNotePrivacy => '您的用户ID、笔记ID和所选原因将提供给管理员审核。';

  @override
  String get reportSubmitting => '正在提交...';

  @override
  String get reportSubmitAction => '提交举报';

  @override
  String get reportSubmitted => '举报已提交。感谢您帮助维护社区安全。';

  @override
  String get reportAlsoBlockUser => '同时屏蔽此用户';

  @override
  String get reportAlsoBlockUserDescription => '提交举报后，此用户的笔记和消息将被隐藏。';

  @override
  String get reportSubmittedBlockFailed => '举报已提交，但未能屏蔽该用户。';

  @override
  String reportFailed(Object error) {
    return '无法提交举报：$error';
  }

  @override
  String get reportCooldown => '请稍候片刻再提交举报。';

  @override
  String get reportUnavailable => '此内容已无法举报。';

  @override
  String get contentModerationUnavailable => '安全检查暂时不可用，请重试。';

  @override
  String get contentNotAllowed => '此内容无法发布，请修改后重试。';

  @override
  String get imageNotAllowed => '无法使用此图片，请选择其他图片。';

  @override
  String get noteCreatedPinImageUploadFailed => '笔记已创建，但无法上传图钉图片。';

  @override
  String get noteCreateNetworkError => '无法连接服务器。请检查网络连接后重试。';

  @override
  String get noteCreateAuthenticationRequired => '请重新登录以创建笔记。';

  @override
  String get noteCreateFailed => '无法创建笔记，请重试。';

  @override
  String get noteCreateUnexpectedError => '发生意外错误，请重试。';

  @override
  String get noteCreateTitle => '新建笔记';

  @override
  String get noteTitleLabel => '标题';

  @override
  String get noteTitleHint => '这是一个怎样的地方？';

  @override
  String get noteTitleRequired => '请输入标题';

  @override
  String get noteDescriptionOptionalLabel => '描述（可选）';

  @override
  String get noteDescriptionHint => '介绍一下这个地方…';

  @override
  String get noteThemeLabel => '笔记主题';

  @override
  String get noteThemeChangeTitle => '更改主题';

  @override
  String get noteThemeChangeDescription => '此更改会影响所有人看到的笔记外观。';

  @override
  String get pinColorLabel => '图钉颜色';

  @override
  String get pinStyleLabel => '图钉样式';

  @override
  String get pinImageLabel => '图钉图片';

  @override
  String get iconLabel => '图标';

  @override
  String get imageLabel => '图片';

  @override
  String get publishLabel => '发布';

  @override
  String get publishNow => '立即';

  @override
  String get publishLater => '稍后';

  @override
  String get publishLaterSchedule => '稍后发布';

  @override
  String get publishIn15Minutes => '15分钟后';

  @override
  String get publishIn30Minutes => '30分钟后';

  @override
  String get publishIn1Hour => '1小时后';

  @override
  String get publishIn3Hours => '3小时后';

  @override
  String get publishTomorrow => '明天';

  @override
  String get publishCustom => '自定义';

  @override
  String get autoCloseAfter => '自动关闭时间';

  @override
  String get autoCloseDescription => '超过此期限后将停止接收消息并归档笔记。';

  @override
  String get expiryOneWeek => '1周';

  @override
  String get expiryOneMonth => '1个月';

  @override
  String expiryMonths(int count) {
    return '$count个月';
  }

  @override
  String get expiryOneYear => '1年';

  @override
  String expiryDays(int count) {
    return '$count天';
  }

  @override
  String get noteAccessLabel => '访问权限';

  @override
  String get createNoteAction => '创建笔记';

  @override
  String get noteCapacityChecking => '正在检查可用笔记名额…';

  @override
  String get noteLimitReached => '已达到笔记上限';

  @override
  String premiumNoteLimitMessage(int count, int limit) {
    return '您正在使用$limit个有效笔记名额中的$count个。请归档一个笔记或等待其到期后再创建。';
  }

  @override
  String freeNoteLimitMessage(int limit, int proLimit) {
    return '免费账户最多可保留$limit个有效笔记。请归档一个笔记，或升级到PRO以使用最多$proLimit个。';
  }

  @override
  String get forkLocationNotice => '新笔记将沿用已归档笔记的位置。';

  @override
  String get noteCreateLocationPermissionRequired => '创建笔记需要位置权限。';

  @override
  String get noteCreateLocationPermissionDisabledMessage =>
      '位置权限已关闭。请打开系统设置并允许位置访问，以便创建笔记。';

  @override
  String get noteCreateLocationServiceDisabledMessage =>
      '位置服务已关闭。请将其打开，以便在当前位置创建笔记。';

  @override
  String get noteCreateLocationUnavailable => '无法获取当前位置，请重试。';

  @override
  String get imagePin => '图片图钉';

  @override
  String get imagePinReady => '图片图钉已就绪';

  @override
  String get pinImageEmptyDescription => '添加裁剪后的缩略图。未设置时将使用默认图钉。';

  @override
  String get pinImageReadyDescription => '将上传此缩略图。';

  @override
  String get chooseImage => '选择图片';

  @override
  String get changeImage => '更换图片';

  @override
  String get removeImage => '移除图片';

  @override
  String get passwordLabel => '密码';

  @override
  String get patternLabel => '图案';

  @override
  String get publicNote => '公开笔记';

  @override
  String get lockedNote => '已锁定笔记';

  @override
  String noteLockSummary(String type) {
    return '$type锁';
  }

  @override
  String noteLockSummaryWithHint(String type) {
    return '带提示的$type锁';
  }

  @override
  String get anyoneNearbyCanOpen => '附近的任何人都可以打开。';

  @override
  String get setLock => '设置锁';

  @override
  String get changeLock => '更改锁';

  @override
  String get removeLock => '移除锁';

  @override
  String get noteThemeStandard => '标准';

  @override
  String get noteThemeStandardDescription => '沉静而熟悉的World Notes标准外观。';

  @override
  String get noteThemeAurora => '极光';

  @override
  String get noteThemeAuroraDescription => '靛蓝与水蓝、紫罗兰光影交织。';

  @override
  String get noteThemeCitrus => '柑橘活力';

  @override
  String get noteThemeCitrusDescription => '温暖的珊瑚橙搭配青绿色点缀。';

  @override
  String get noteThemeBotanical => '植物园';

  @override
  String get noteThemeBotanicalDescription => '沉稳的翡翠色与叶绿色。';

  @override
  String get noteThemeNeon => '霓虹网格';

  @override
  String get noteThemeNeonDescription => '暗色中的青蓝与紫红霓虹。';

  @override
  String get noteThemeEditorial => '杂志';

  @override
  String get noteThemeEditorialDescription => '纸张般的中性色配以钴蓝点缀。';

  @override
  String get noteFallbackTitle => '笔记';

  @override
  String get noteUnavailableTitle => '此笔记当前不可用。';

  @override
  String get noteUnavailableMessage => '它可能尚未发布、已经过期，或无法再从当前位置访问。';

  @override
  String get noteOpenFailedTitle => '无法打开此笔记。';

  @override
  String get noteOpenFailedMessage => '请检查网络连接，并确认您仍在笔记附近。';

  @override
  String get noteReadOnlyFromMyNotes => '从“我的笔记”打开时为只读。';

  @override
  String get notePrivateTitle => '这是一则私密笔记';

  @override
  String get notePrivatePasswordDescription => '请输入密码以阅读和发布消息。';

  @override
  String get notePrivatePatternDescription => '请绘制图案以阅读和发布消息。';

  @override
  String get notePrivateDescription => '请解锁笔记以阅读和发布消息。';

  @override
  String get enterPassword => '输入密码';

  @override
  String get drawPattern => '绘制图案';

  @override
  String get unlockAction => '解锁';

  @override
  String noteLockHint(String hint) {
    return '提示：$hint';
  }

  @override
  String get noteScheduledReadOnly => '此笔记已预约发布，目前尚不接收消息。';

  @override
  String get noteArchivedReadOnly => '此笔记已归档，仅供阅读。';

  @override
  String threadMessageLimitReached(int count) {
    return '此讨论串已达到$count条消息的上限，现已关闭。';
  }

  @override
  String get threadFullClosed => '此讨论串已满并关闭。';

  @override
  String get threadMaintainerClosed => '管理员已关闭此讨论串，仅供阅读。';

  @override
  String get closeThreadAction => '关闭讨论串';

  @override
  String get reopenThreadAction => '重新打开讨论串';

  @override
  String get changeThemeAction => '更改主题';

  @override
  String get manageAccessAction => '管理访问权限';

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
  String get blockUserAction => '屏蔽用户';

  @override
  String get unblockUserAction => '取消屏蔽';

  @override
  String blockUserTitle(String name) {
    return '屏蔽$name？';
  }

  @override
  String get blockUserConfirmation =>
      '此用户的笔记和消息将被隐藏。你们会互相取消关注，且对方将失去访问你所拥有笔记的权限。在其他人拥有的笔记中，你们仍可能同时出现。';

  @override
  String get blockUserConfirmAction => '屏蔽';

  @override
  String unblockUserTitle(String name) {
    return '取消屏蔽$name？';
  }

  @override
  String get unblockUserConfirmation => '此用户的内容可能会重新显示。之前的关注关系以及对你笔记的访问权限不会恢复。';

  @override
  String userBlocked(String name) {
    return '已屏蔽$name。';
  }

  @override
  String userUnblocked(String name) {
    return '已取消屏蔽$name。';
  }

  @override
  String updateUserBlockFailed(Object error) {
    return '无法更新屏蔽设置：$error';
  }

  @override
  String get settingsTitle => '设置';

  @override
  String get blockedUsersTitle => '已屏蔽的用户';

  @override
  String get blockedUsersDescription => '查看或取消屏蔽用户';

  @override
  String get noBlockedUsers => '你尚未屏蔽任何用户。';

  @override
  String blockedUsersLoadFailed(Object error) {
    return '无法加载已屏蔽的用户：$error';
  }

  @override
  String get settingsLanguageTitle => '应用语言';

  @override
  String get settingsLanguageSystem => '自动（系统）';

  @override
  String get settingsLanguageSystemDescription => '使用设备的语言设置';

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
  String get settingsLanguageUpdateFailed => '此设备的显示语言已更改，但无法保存到你的账户。';

  @override
  String get settingsMapStyleTitle => '地图样式';

  @override
  String get settingsMapStyleAuto => '自动';

  @override
  String get settingsMapStyleStandard => '标准';

  @override
  String get settingsMapStyleLight => '浅色';

  @override
  String get settingsMapStyleDark => '深色';

  @override
  String get settingsMapStylePop => '鲜艳';

  @override
  String get settingsMapStyleAutoDescription => '跟随系统外观';

  @override
  String get settingsMapStyleStandardDescription => '简洁清晰的显示';

  @override
  String get settingsMapStyleLightDescription => '以浅色模式使用 Apple 地图';

  @override
  String get settingsMapStyleDarkDescription => '夜间更舒适的深色显示';

  @override
  String get settingsMapStylePopDescription => '明亮多彩的显示';

  @override
  String get settingsDataRegionTitle => '数据区域';

  @override
  String get settingsDataRegionDescription =>
      '选择处理请求的区域。自动会选择离当前位置最近的区域，旅行时也可手动更改。';

  @override
  String get settingsDataRegionAuto => '自动（最近）';

  @override
  String settingsDataRegionCurrent(String region) {
    return '当前：$region';
  }

  @override
  String get settingsRegionAsiaTokyo => '亚洲（东京）';

  @override
  String get settingsRegionAmericasUsCentral => '美洲（美国中部）';

  @override
  String get settingsRegionEuropeBelgium => '欧洲（比利时）';

  @override
  String get settingsNotificationsTitle => '通知';

  @override
  String get notificationsMaintainedNotesTitle => '管理中的笔记';

  @override
  String get notificationsMaintainedNotesDescription => '你管理的笔记收到新消息时通知你。';

  @override
  String get notificationsTurnOnTooltip => '开启管理中笔记的通知';

  @override
  String get notificationsTurnOffTooltip => '关闭管理中笔记的通知';

  @override
  String get notificationsPermissionDenied => '通知未获允许。请在系统设置中启用通知以接收新消息提醒。';

  @override
  String get notificationsEnableFailed => '无法开启管理中笔记的通知。';

  @override
  String get notificationsDisableFailed => '无法关闭管理中笔记的通知。';

  @override
  String get notificationPreviewsTitle => '消息预览';

  @override
  String get notificationPreviewsDescription => '在管理中笔记的通知里显示消息内容。';

  @override
  String get notificationPreviewsUpdateFailed => '无法更新通知预览。';

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
  String get noNotifications => '目前沒有通知。';

  @override
  String get noFollowers => '目前沒有追蹤者。';

  @override
  String get noFollowing => '尚未追蹤任何人。';

  @override
  String get noFootprints => '目前沒有足跡。';

  @override
  String get noFootprintsDescription => '訪客開啟此筆記後會顯示在這裡。';

  @override
  String get noAccessMembers => '目前尚無人擁有存取權限。分享連結即可新增成員。';

  @override
  String get noModerationReviews => '目前沒有審查項目。';

  @override
  String get youLabel => '你';

  @override
  String get messageSending => '傳送中…';

  @override
  String messageScheduledAt(String time) {
    return '預定於 $time 發佈';
  }

  @override
  String get reportMessageAction => '檢舉訊息';

  @override
  String get reportNoteAction => '檢舉筆記';

  @override
  String get reportMessageTitle => '檢舉訊息';

  @override
  String get reportNoteTitle => '檢舉筆記';

  @override
  String get reportMessageQuestion => '為什麼要檢舉這則訊息？';

  @override
  String get reportNoteQuestion => '為什麼要檢舉這篇筆記？';

  @override
  String get reportReasonSpam => '垃圾訊息或廣告';

  @override
  String get reportReasonHarassment => '騷擾或霸凌';

  @override
  String get reportReasonSexual => '成人或露骨內容';

  @override
  String get reportReasonIllegal => '違法內容';

  @override
  String get reportReasonOther => '其他';

  @override
  String get reportMessagePrivacy => '您的使用者ID、訊息ID、筆記ID和所選原因將提供給管理員審核。';

  @override
  String get reportNotePrivacy => '您的使用者ID、筆記ID和所選原因將提供給管理員審核。';

  @override
  String get reportSubmitting => '正在提交...';

  @override
  String get reportSubmitAction => '提交檢舉';

  @override
  String get reportSubmitted => '檢舉已提交。感謝您協助維護社群安全。';

  @override
  String get reportAlsoBlockUser => '同時封鎖此使用者';

  @override
  String get reportAlsoBlockUserDescription => '提交檢舉後，此使用者的筆記和訊息將被隱藏。';

  @override
  String get reportSubmittedBlockFailed => '檢舉已提交，但無法封鎖該使用者。';

  @override
  String reportFailed(Object error) {
    return '無法提交檢舉：$error';
  }

  @override
  String get reportCooldown => '請稍候片刻再提交檢舉。';

  @override
  String get reportUnavailable => '此內容已無法檢舉。';

  @override
  String get contentModerationUnavailable => '安全檢查暫時無法使用，請再試一次。';

  @override
  String get contentNotAllowed => '此內容無法發布，請修改後再試一次。';

  @override
  String get imageNotAllowed => '無法使用此圖片，請選擇其他圖片。';

  @override
  String get noteCreatedPinImageUploadFailed => '筆記已建立，但無法上傳圖釘圖片。';

  @override
  String get noteCreateNetworkError => '無法連線至伺服器。請檢查網路連線後再試一次。';

  @override
  String get noteCreateAuthenticationRequired => '請重新登入以建立筆記。';

  @override
  String get noteCreateFailed => '無法建立筆記，請再試一次。';

  @override
  String get noteCreateUnexpectedError => '發生未預期的錯誤，請再試一次。';

  @override
  String get noteCreateTitle => '新增筆記';

  @override
  String get noteTitleLabel => '標題';

  @override
  String get noteTitleHint => '這是什麼樣的地方？';

  @override
  String get noteTitleRequired => '請輸入標題';

  @override
  String get noteDescriptionOptionalLabel => '描述（選填）';

  @override
  String get noteDescriptionHint => '介紹一下這個地方…';

  @override
  String get noteThemeLabel => '筆記主題';

  @override
  String get noteThemeChangeTitle => '變更主題';

  @override
  String get noteThemeChangeDescription => '此變更會影響所有人看到的筆記外觀。';

  @override
  String get pinColorLabel => '圖釘顏色';

  @override
  String get pinStyleLabel => '圖釘樣式';

  @override
  String get pinImageLabel => '圖釘圖片';

  @override
  String get iconLabel => '圖示';

  @override
  String get imageLabel => '圖片';

  @override
  String get publishLabel => '發布';

  @override
  String get publishNow => '立即';

  @override
  String get publishLater => '稍後';

  @override
  String get publishLaterSchedule => '稍後發布';

  @override
  String get publishIn15Minutes => '15分鐘後';

  @override
  String get publishIn30Minutes => '30分鐘後';

  @override
  String get publishIn1Hour => '1小時後';

  @override
  String get publishIn3Hours => '3小時後';

  @override
  String get publishTomorrow => '明天';

  @override
  String get publishCustom => '自訂';

  @override
  String get autoCloseAfter => '自動關閉時間';

  @override
  String get autoCloseDescription => '超過此期限後將停止接收訊息並封存筆記。';

  @override
  String get expiryOneWeek => '1週';

  @override
  String get expiryOneMonth => '1個月';

  @override
  String expiryMonths(int count) {
    return '$count個月';
  }

  @override
  String get expiryOneYear => '1年';

  @override
  String expiryDays(int count) {
    return '$count天';
  }

  @override
  String get noteAccessLabel => '存取權限';

  @override
  String get createNoteAction => '建立筆記';

  @override
  String get noteCapacityChecking => '正在檢查可用筆記名額…';

  @override
  String get noteLimitReached => '已達筆記上限';

  @override
  String premiumNoteLimitMessage(int count, int limit) {
    return '您正在使用$limit個有效筆記名額中的$count個。請封存一則筆記或等待其到期後再建立。';
  }

  @override
  String freeNoteLimitMessage(int limit, int proLimit) {
    return '免費帳戶最多可保留$limit則有效筆記。請封存一則筆記，或升級至PRO以使用最多$proLimit則。';
  }

  @override
  String get forkLocationNotice => '新筆記將沿用已封存筆記的位置。';

  @override
  String get noteCreateLocationPermissionRequired => '建立筆記需要位置權限。';

  @override
  String get noteCreateLocationPermissionDisabledMessage =>
      '位置權限已關閉。請開啟系統設定並允許位置存取，以便建立筆記。';

  @override
  String get noteCreateLocationServiceDisabledMessage =>
      '位置服務已關閉。請將其開啟，以便在目前位置建立筆記。';

  @override
  String get noteCreateLocationUnavailable => '無法取得目前位置，請再試一次。';

  @override
  String get imagePin => '圖片圖釘';

  @override
  String get imagePinReady => '圖片圖釘已就緒';

  @override
  String get pinImageEmptyDescription => '加入裁切後的縮圖。未設定時將使用預設圖釘。';

  @override
  String get pinImageReadyDescription => '將上傳此縮圖。';

  @override
  String get chooseImage => '選擇圖片';

  @override
  String get changeImage => '更換圖片';

  @override
  String get removeImage => '移除圖片';

  @override
  String get passwordLabel => '密碼';

  @override
  String get patternLabel => '圖形';

  @override
  String get publicNote => '公開筆記';

  @override
  String get lockedNote => '已鎖定筆記';

  @override
  String noteLockSummary(String type) {
    return '$type鎖';
  }

  @override
  String noteLockSummaryWithHint(String type) {
    return '附提示的$type鎖';
  }

  @override
  String get anyoneNearbyCanOpen => '附近的任何人都可以開啟。';

  @override
  String get setLock => '設定鎖';

  @override
  String get changeLock => '變更鎖';

  @override
  String get removeLock => '移除鎖';

  @override
  String get noteThemeStandard => '標準';

  @override
  String get noteThemeStandardDescription => '沉靜而熟悉的World Notes標準外觀。';

  @override
  String get noteThemeAurora => '極光';

  @override
  String get noteThemeAuroraDescription => '靛藍與水藍、紫羅蘭光影交織。';

  @override
  String get noteThemeCitrus => '柑橘活力';

  @override
  String get noteThemeCitrusDescription => '溫暖的珊瑚橙搭配藍綠色點綴。';

  @override
  String get noteThemeBotanical => '植物園';

  @override
  String get noteThemeBotanicalDescription => '沉穩的翡翠色與葉綠色。';

  @override
  String get noteThemeNeon => '霓虹網格';

  @override
  String get noteThemeNeonDescription => '暗色中的青藍與紫紅霓虹。';

  @override
  String get noteThemeEditorial => '雜誌';

  @override
  String get noteThemeEditorialDescription => '紙張般的中性色配以鈷藍點綴。';

  @override
  String get noteFallbackTitle => '筆記';

  @override
  String get noteUnavailableTitle => '此筆記目前無法使用。';

  @override
  String get noteUnavailableMessage => '它可能尚未發布、已經過期，或無法再從目前位置存取。';

  @override
  String get noteOpenFailedTitle => '無法開啟此筆記。';

  @override
  String get noteOpenFailedMessage => '請檢查網路連線，並確認您仍在筆記附近。';

  @override
  String get noteReadOnlyFromMyNotes => '從「我的筆記」開啟時為唯讀。';

  @override
  String get notePrivateTitle => '這是一則私人筆記';

  @override
  String get notePrivatePasswordDescription => '請輸入密碼以閱讀和發布訊息。';

  @override
  String get notePrivatePatternDescription => '請繪製圖形以閱讀和發布訊息。';

  @override
  String get notePrivateDescription => '請解鎖筆記以閱讀和發布訊息。';

  @override
  String get enterPassword => '輸入密碼';

  @override
  String get drawPattern => '繪製圖形';

  @override
  String get unlockAction => '解鎖';

  @override
  String noteLockHint(String hint) {
    return '提示：$hint';
  }

  @override
  String get noteScheduledReadOnly => '此筆記已預約發布，目前尚不接收訊息。';

  @override
  String get noteArchivedReadOnly => '此筆記已封存，僅供閱讀。';

  @override
  String threadMessageLimitReached(int count) {
    return '此討論串已達$count則訊息的上限，現已關閉。';
  }

  @override
  String get threadFullClosed => '此討論串已滿並關閉。';

  @override
  String get threadMaintainerClosed => '管理員已關閉此討論串，僅供閱讀。';

  @override
  String get closeThreadAction => '關閉討論串';

  @override
  String get reopenThreadAction => '重新開啟討論串';

  @override
  String get changeThemeAction => '變更主題';

  @override
  String get manageAccessAction => '管理存取權限';

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
  String get blockUserAction => '封鎖使用者';

  @override
  String get unblockUserAction => '解除封鎖';

  @override
  String blockUserTitle(String name) {
    return '封鎖$name？';
  }

  @override
  String get blockUserConfirmation =>
      '此使用者的筆記和訊息將被隱藏。你們會互相取消追蹤，且對方將失去存取你所擁有筆記的權限。在其他人擁有的筆記中，你們仍可能同時出現。';

  @override
  String get blockUserConfirmAction => '封鎖';

  @override
  String unblockUserTitle(String name) {
    return '解除封鎖$name？';
  }

  @override
  String get unblockUserConfirmation =>
      '此使用者的內容可能會再次顯示。先前的追蹤關係以及對你筆記的存取權限不會恢復。';

  @override
  String userBlocked(String name) {
    return '已封鎖$name。';
  }

  @override
  String userUnblocked(String name) {
    return '已解除封鎖$name。';
  }

  @override
  String updateUserBlockFailed(Object error) {
    return '無法更新封鎖設定：$error';
  }

  @override
  String get settingsTitle => '設定';

  @override
  String get blockedUsersTitle => '已封鎖的使用者';

  @override
  String get blockedUsersDescription => '查看或解除封鎖使用者';

  @override
  String get noBlockedUsers => '你尚未封鎖任何使用者。';

  @override
  String blockedUsersLoadFailed(Object error) {
    return '無法載入已封鎖的使用者：$error';
  }

  @override
  String get settingsLanguageTitle => 'App 語言';

  @override
  String get settingsLanguageSystem => '自動（系統）';

  @override
  String get settingsLanguageSystemDescription => '使用裝置的語言設定';

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
  String get settingsLanguageUpdateFailed => '此裝置的顯示語言已變更，但無法儲存到你的帳號。';

  @override
  String get settingsMapStyleTitle => '地圖樣式';

  @override
  String get settingsMapStyleAuto => '自動';

  @override
  String get settingsMapStyleStandard => '標準';

  @override
  String get settingsMapStyleLight => '淺色';

  @override
  String get settingsMapStyleDark => '深色';

  @override
  String get settingsMapStylePop => '鮮豔';

  @override
  String get settingsMapStyleAutoDescription => '跟隨系統外觀';

  @override
  String get settingsMapStyleStandardDescription => '簡潔清晰的顯示';

  @override
  String get settingsMapStyleLightDescription => '以淺色模式使用 Apple 地圖';

  @override
  String get settingsMapStyleDarkDescription => '夜間更舒適的深色顯示';

  @override
  String get settingsMapStylePopDescription => '明亮多彩的顯示';

  @override
  String get settingsDataRegionTitle => '資料區域';

  @override
  String get settingsDataRegionDescription =>
      '選擇處理請求的區域。自動會選擇離目前位置最近的區域，旅行時也可手動變更。';

  @override
  String get settingsDataRegionAuto => '自動（最近）';

  @override
  String settingsDataRegionCurrent(String region) {
    return '目前：$region';
  }

  @override
  String get settingsRegionAsiaTokyo => '亞洲（東京）';

  @override
  String get settingsRegionAmericasUsCentral => '美洲（美國中部）';

  @override
  String get settingsRegionEuropeBelgium => '歐洲（比利時）';

  @override
  String get settingsNotificationsTitle => '通知';

  @override
  String get notificationsMaintainedNotesTitle => '管理中的筆記';

  @override
  String get notificationsMaintainedNotesDescription => '你管理的筆記收到新訊息時通知你。';

  @override
  String get notificationsTurnOnTooltip => '開啟管理中筆記的通知';

  @override
  String get notificationsTurnOffTooltip => '關閉管理中筆記的通知';

  @override
  String get notificationsPermissionDenied => '通知未獲允許。請在系統設定中啟用通知以接收新訊息提醒。';

  @override
  String get notificationsEnableFailed => '無法開啟管理中筆記的通知。';

  @override
  String get notificationsDisableFailed => '無法關閉管理中筆記的通知。';

  @override
  String get notificationPreviewsTitle => '訊息預覽';

  @override
  String get notificationPreviewsDescription => '在管理中筆記的通知裡顯示訊息內容。';

  @override
  String get notificationPreviewsUpdateFailed => '無法更新通知預覽。';

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
