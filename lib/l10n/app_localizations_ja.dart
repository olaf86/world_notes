// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appName => 'セカイノート';

  @override
  String get commonCancel => 'キャンセル';

  @override
  String get commonSave => '保存';

  @override
  String get commonRetry => '再試行';

  @override
  String get commonTryAgain => 'もう一度試す';

  @override
  String commonError(Object error) {
    return 'エラー: $error';
  }

  @override
  String get navMap => 'マップ';

  @override
  String get navNotes => 'ノート';

  @override
  String get navNotifications => 'お知らせ';

  @override
  String get navProfile => 'プロフィール';

  @override
  String get locationPermissionTitle => '現在位置へのアクセスが必要です';

  @override
  String get locationPermissionMessage =>
      'セカイノートを楽しむために、現在位置のトラッキング許可を有効にしてください。';

  @override
  String get locationPermissionOpenSettings => '設定を開く';

  @override
  String get locationPermissionAllow => '現在位置を許可';

  @override
  String get locationServiceDisabledTitle => '位置情報サービスをオンにしてください';

  @override
  String get locationServiceDisabledMessage =>
      'セカイノートを利用するには、端末の位置情報サービスをオンにしてください。';

  @override
  String get locationServiceOpenSettings => '位置情報設定を開く';

  @override
  String get locationSearching => '現在位置を取得中…';

  @override
  String get locationUnavailable => '位置情報を利用できません。';

  @override
  String get locationUnavailableHelp =>
      '設定で位置情報へのアクセスを許可するか、\nGPSを受信しやすい場所へ移動してください。';

  @override
  String get locationLoadFailed => '位置情報を取得できませんでした。';

  @override
  String get currentLocationUnavailable => '現在位置を取得できませんでした。';

  @override
  String get enableLocation => '位置情報を有効にする';

  @override
  String get enableLocationSettingsTooltip => '設定を開いて位置情報を有効にする';

  @override
  String get enableLocationPermissionTooltip => '位置情報を許可してノートを追加する';

  @override
  String get enableLocationServiceTooltip => '位置情報設定を開く';

  @override
  String get mapNotesTitle => '周辺のノート';

  @override
  String get mapAddNote => 'ノートを作成';

  @override
  String get mapList => '一覧';

  @override
  String get mapRefreshNotes => '周辺のノートを更新';

  @override
  String mapHideAccessArea(String radius) {
    return '$radiusのアクセス範囲を非表示';
  }

  @override
  String mapShowAccessArea(String radius) {
    return '$radiusのアクセス範囲を表示';
  }

  @override
  String get mapLoadingNotes => '周辺のノートを読み込み中…';

  @override
  String get mapNoNotes => 'このエリアにはまだノートがありません。\nマップを移動するか、ここにノートを置いてみましょう！';

  @override
  String mapDistanceMeters(int distance) {
    return '$distance m先';
  }

  @override
  String mapDistanceKilometers(String distance) {
    return '$distance km先';
  }

  @override
  String get mapFromFollowing => 'フォロー中のユーザーから';

  @override
  String get mapNewFromFollowing => 'フォロー中のユーザーから新着';

  @override
  String get mapFromFollowingSemantic => 'フォロー中のユーザーが作成したノートです。';

  @override
  String get newMessages => '新着メッセージ';

  @override
  String createdAt(String date) {
    return '作成日時 $date';
  }

  @override
  String expiresAt(String date) {
    return '期限 $date';
  }

  @override
  String get noteClosed => '終了';

  @override
  String get notePrivate => '非公開';

  @override
  String get noteWithinRange => 'アクセス範囲内です。このノートを開けます。';

  @override
  String get noteOutsideRange => 'アクセス範囲外です。近づくとこのノートを開けます。';

  @override
  String get noteOpenNow => '今すぐ開く';

  @override
  String get noteMoveCloser => '近づいて開く';

  @override
  String messageCount(int count) {
    return 'メッセージ $count件';
  }

  @override
  String likeCount(int count) {
    return 'いいね $count件';
  }

  @override
  String footprintCount(int count) {
    return '足あと $count件';
  }

  @override
  String get footprintsOn => '足あと記録オン';

  @override
  String get footprintsOff => '足あと記録オフ';

  @override
  String get noteOpening => '開いています…';

  @override
  String get noteView => 'ノートを見る';

  @override
  String get noteOpen => 'ノートを開く';

  @override
  String get noteAvailableNearby => '近づくと開けます';

  @override
  String get noteExpired => '期限切れ';

  @override
  String noteExpiresMonths(int count) {
    return 'あと$countか月';
  }

  @override
  String noteExpiresDays(int count) {
    return 'あと$count日';
  }

  @override
  String noteExpiresHours(int count) {
    return 'あと$count時間';
  }

  @override
  String get noteExpiresSoon => 'まもなく期限切れ';

  @override
  String get goPro => 'PROを見る';

  @override
  String get threadOptions => 'ノートの操作';

  @override
  String get writeMessage => 'メッセージを書く';

  @override
  String get likeNote => 'ノートにいいね';

  @override
  String get unlikeNote => 'ノートのいいねを解除';

  @override
  String get cannotLikeOwnNote => '自分のノートにはいいねできません';

  @override
  String get likeUnavailable => 'いいねできません';

  @override
  String get noMessages => 'メッセージはまだありません。\n最初のメッセージを書いてみましょう！';

  @override
  String get youLabel => 'あなた';

  @override
  String get messageSending => '送信中…';

  @override
  String messageScheduledAt(String time) {
    return '$timeに公開予定';
  }

  @override
  String get noteCreateTitle => '新しいノート';

  @override
  String get noteTitleLabel => 'タイトル';

  @override
  String get noteTitleHint => 'どんな場所ですか？';

  @override
  String get noteTitleRequired => 'タイトルを入力してください';

  @override
  String get noteDescriptionOptionalLabel => '説明（任意）';

  @override
  String get noteDescriptionHint => 'この場所について教えてください…';

  @override
  String get noteThemeLabel => 'ノートテーマ';

  @override
  String get noteThemeChangeTitle => 'テーマを変更';

  @override
  String get noteThemeChangeDescription => 'この変更は、すべてのユーザーが見るノートの外観に反映されます。';

  @override
  String get pinColorLabel => 'ピンの色';

  @override
  String get pinStyleLabel => 'ピンのスタイル';

  @override
  String get pinImageLabel => 'ピン画像';

  @override
  String get iconLabel => 'アイコン';

  @override
  String get imageLabel => '画像';

  @override
  String get publishLabel => '公開';

  @override
  String get publishNow => '今すぐ';

  @override
  String get publishLater => 'あとで';

  @override
  String get publishLaterSchedule => 'あとで公開';

  @override
  String get publishIn15Minutes => '15分後';

  @override
  String get publishIn30Minutes => '30分後';

  @override
  String get publishIn1Hour => '1時間後';

  @override
  String get publishIn3Hours => '3時間後';

  @override
  String get publishTomorrow => '明日';

  @override
  String get publishCustom => '日時を指定';

  @override
  String get autoCloseAfter => '自動で閉じるまで';

  @override
  String get autoCloseDescription => 'この期間を過ぎるとメッセージの受付を終了し、ノートをアーカイブします。';

  @override
  String get expiryOneWeek => '1週間';

  @override
  String get expiryOneMonth => '1か月';

  @override
  String expiryMonths(int count) {
    return '$countか月';
  }

  @override
  String get expiryOneYear => '1年';

  @override
  String expiryDays(int count) {
    return '$count日';
  }

  @override
  String get noteAccessLabel => 'アクセス';

  @override
  String get createNoteAction => 'ノートを作成';

  @override
  String get noteCapacityChecking => '利用可能なノート枠を確認中…';

  @override
  String get noteLimitReached => 'ノートの上限に達しました';

  @override
  String premiumNoteLimitMessage(int count, int limit) {
    return '有効なノートは$limit件中$count件です。新しく作成するには、いずれかをアーカイブするか期限切れをお待ちください。';
  }

  @override
  String freeNoteLimitMessage(int limit, int proLimit) {
    return '無料アカウントでは有効なノートを$limit件まで保持できます。いずれかをアーカイブするか、PROにアップグレードすると$proLimit件まで利用できます。';
  }

  @override
  String get forkLocationNotice => 'アーカイブしたノートの場所を引き継いで新しいノートを作成します。';

  @override
  String get noteCreateLocationPermissionRequired => 'ノートを作成するには位置情報の許可が必要です。';

  @override
  String get noteCreateLocationPermissionDisabledMessage =>
      '位置情報の許可が無効です。システム設定を開き、ノートを作成できるよう位置情報へのアクセスを許可してください。';

  @override
  String get noteCreateLocationServiceDisabledMessage =>
      '位置情報サービスがオフです。現在地にノートを作成するにはオンにしてください。';

  @override
  String get noteCreateLocationUnavailable => '現在地を取得できませんでした。もう一度お試しください。';

  @override
  String get imagePin => '画像ピン';

  @override
  String get imagePinReady => '画像ピンの準備完了';

  @override
  String get pinImageEmptyDescription => '切り抜いたサムネイルを追加できます。未設定時は標準のピンを使用します。';

  @override
  String get pinImageReadyDescription => 'このサムネイルをアップロードします。';

  @override
  String get chooseImage => '画像を選択';

  @override
  String get changeImage => '画像を変更';

  @override
  String get removeImage => '画像を削除';

  @override
  String get passwordLabel => 'パスワード';

  @override
  String get patternLabel => 'パターン';

  @override
  String get publicNote => '公開ノート';

  @override
  String get lockedNote => 'ロック付きノート';

  @override
  String noteLockSummary(String type) {
    return '$typeロック';
  }

  @override
  String noteLockSummaryWithHint(String type) {
    return 'ヒント付き$typeロック';
  }

  @override
  String get anyoneNearbyCanOpen => '近くにいる人なら誰でも開けます。';

  @override
  String get setLock => 'ロックを設定';

  @override
  String get changeLock => 'ロックを変更';

  @override
  String get removeLock => 'ロックを解除';

  @override
  String get noteThemeStandard => 'スタンダード';

  @override
  String get noteThemeStandardDescription => '落ち着きのある、親しみやすい標準デザイン。';

  @override
  String get noteThemeAurora => 'オーロラ';

  @override
  String get noteThemeAuroraDescription => '藍色にアクアと紫の光を重ねたデザイン。';

  @override
  String get noteThemeCitrus => 'シトラスポップ';

  @override
  String get noteThemeCitrusDescription => '暖かなコーラルとオレンジにティールのアクセント。';

  @override
  String get noteThemeBotanical => 'ボタニカル';

  @override
  String get noteThemeBotanicalDescription => '翡翠色と葉の緑を基調にしたデザイン。';

  @override
  String get noteThemeNeon => 'ネオングリッド';

  @override
  String get noteThemeNeonDescription => '暗闇に映えるシアンとフューシャのデザイン。';

  @override
  String get noteThemeEditorial => 'エディトリアル';

  @override
  String get noteThemeEditorialDescription => '紙のような中間色にコバルトのアクセント。';

  @override
  String get noteFallbackTitle => 'ノート';

  @override
  String get noteUnavailableTitle => 'このノートは利用できません。';

  @override
  String get noteUnavailableMessage =>
      'まだ公開されていない、期限切れになった、または現在地からアクセスできなくなった可能性があります。';

  @override
  String get noteOpenFailedTitle => 'ノートを開けませんでした。';

  @override
  String get noteOpenFailedMessage => '通信状態と、ノートの近くにいることを確認してください。';

  @override
  String get noteReadOnlyFromMyNotes => 'マイノートからは閲覧のみです。';

  @override
  String get notePrivateTitle => 'このノートは非公開です';

  @override
  String get notePrivatePasswordDescription => 'メッセージを読む・投稿するにはパスワードを入力してください。';

  @override
  String get notePrivatePatternDescription => 'メッセージを読む・投稿するにはパターンを描いてください。';

  @override
  String get notePrivateDescription => 'メッセージを読む・投稿するにはノートのロックを解除してください。';

  @override
  String get enterPassword => 'パスワードを入力';

  @override
  String get drawPattern => 'パターンを描く';

  @override
  String get unlockAction => 'ロックを解除';

  @override
  String noteLockHint(String hint) {
    return 'ヒント: $hint';
  }

  @override
  String get noteScheduledReadOnly => 'このノートは公開予約中のため、まだメッセージを受け付けていません。';

  @override
  String get noteArchivedReadOnly => 'このノートはアーカイブ済みです。閲覧のみできます。';

  @override
  String threadMessageLimitReached(int count) {
    return 'このスレッドはメッセージ上限の$count件に達したため終了しました。';
  }

  @override
  String get threadFullClosed => 'このスレッドは満杯のため終了しました。';

  @override
  String get threadMaintainerClosed => '管理者がこのスレッドを終了しました。閲覧のみできます。';

  @override
  String get closeThreadAction => 'スレッドを終了';

  @override
  String get reopenThreadAction => 'スレッドを再開';

  @override
  String get changeThemeAction => 'テーマを変更';

  @override
  String get manageAccessAction => 'アクセスを管理';

  @override
  String sortNotesTooltip(String sort) {
    return 'ノートを並べ替え: $sort';
  }

  @override
  String sortNotesSelected(String sort) {
    return 'ノートの並び順: $sort';
  }

  @override
  String sortedBy(String sort) {
    return '並び順: $sort';
  }

  @override
  String get sortDistance => '距離が近い順';

  @override
  String get sortLastActivity => '更新が新しい順';

  @override
  String get sortNewest => '作成が新しい順';

  @override
  String get sortExpiresSoon => '期限が近い順';

  @override
  String get sortMostLiked => 'いいねが多い順';

  @override
  String get sortArchivedNewest => '最近アーカイブ';

  @override
  String get sortArchivedOldest => '古いアーカイブ';

  @override
  String get myNotesTitle => 'ノート';

  @override
  String get myNotesTab => 'マイノート';

  @override
  String get archivedNotesTab => 'アーカイブ';

  @override
  String get archiveNoteTitle => 'このノートをアーカイブしますか？';

  @override
  String get archiveNoteMessage =>
      'マップから非表示になり、読み取り専用となって、ノート枠が1件空きます。元には戻せませんが、あとからタイトル・説明・場所を引き継いだ新しいノートを作成できます。';

  @override
  String get archiveAction => 'アーカイブ';

  @override
  String archiveFailed(Object error) {
    return 'ノートをアーカイブできませんでした: $error';
  }

  @override
  String get loadMore => 'さらに読み込む';

  @override
  String get retryLoadMore => '再読み込み';

  @override
  String get createdNotes => '作成したノート';

  @override
  String get archivedNotes => 'アーカイブしたノート';

  @override
  String lastActive(String time) {
    return '最終更新 $time';
  }

  @override
  String archivedAt(String time) {
    return 'アーカイブ $time';
  }

  @override
  String get createFromArchiveTooltip => 'アーカイブから新しいノートを作成';

  @override
  String get archiveNoteTooltip => 'ノートをアーカイブ';

  @override
  String relativeDaysAgo(int count) {
    return '$count日前';
  }

  @override
  String relativeHoursAgo(int count) {
    return '$count時間前';
  }

  @override
  String relativeMinutesAgo(int count) {
    return '$count分前';
  }

  @override
  String get relativeJustNow => 'たった今';

  @override
  String get noArchivedNotes => 'アーカイブしたノートはまだありません。';

  @override
  String get noMyNotes => 'ノートはまだありません。\nマップタブから作成してみましょう。';

  @override
  String get profileTitle => 'プロフィール';

  @override
  String get settingsTitle => '設定';

  @override
  String get settingsLanguageTitle => 'アプリの言語';

  @override
  String get settingsLanguageSystem => '自動（システム）';

  @override
  String get settingsLanguageSystemDescription => '端末の言語設定を使用します';

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
      'この端末の表示言語は変更されましたが、アカウントに保存できませんでした。';

  @override
  String get settingsMapStyleTitle => 'マップスタイル';

  @override
  String get settingsMapStyleAuto => '自動';

  @override
  String get settingsMapStyleStandard => '標準';

  @override
  String get settingsMapStyleLight => 'ライト';

  @override
  String get settingsMapStyleDark => 'ダーク';

  @override
  String get settingsMapStylePop => 'ポップ';

  @override
  String get settingsMapStyleAutoDescription => 'システムの外観に合わせます';

  @override
  String get settingsMapStyleStandardDescription => 'すっきりとした標準表示';

  @override
  String get settingsMapStyleLightDescription => 'Appleマップをライト表示で使用します';

  @override
  String get settingsMapStyleDarkDescription => '夜間でも見やすい暗い表示';

  @override
  String get settingsMapStylePopDescription => '明るくカラフルな表示';

  @override
  String get settingsDataRegionTitle => 'データリージョン';

  @override
  String get settingsDataRegionDescription =>
      'リクエストを処理するリージョンを選択します。自動では現在地に最も近いリージョンが選ばれ、旅行中は手動で変更できます。';

  @override
  String get settingsDataRegionAuto => '自動（最寄り）';

  @override
  String settingsDataRegionCurrent(String region) {
    return '現在: $region';
  }

  @override
  String get settingsRegionAsiaTokyo => 'アジア（東京）';

  @override
  String get settingsRegionAmericasUsCentral => 'アメリカ（米国中部）';

  @override
  String get settingsRegionEuropeBelgium => 'ヨーロッパ（ベルギー）';

  @override
  String get settingsNotificationsTitle => '通知';

  @override
  String get notificationsMaintainedNotesTitle => '管理中のノート';

  @override
  String get notificationsMaintainedNotesDescription =>
      '管理しているノートに新しいメッセージが届いたときに通知します。';

  @override
  String get notificationsTurnOnTooltip => '管理中のノートの通知をオンにする';

  @override
  String get notificationsTurnOffTooltip => '管理中のノートの通知をオフにする';

  @override
  String get notificationsPermissionDenied =>
      '通知が許可されていません。新着メッセージを受け取るには、システム設定で通知を有効にしてください。';

  @override
  String get notificationsEnableFailed => '管理中のノートの通知を有効にできませんでした。';

  @override
  String get notificationsDisableFailed => '管理中のノートの通知を無効にできませんでした。';

  @override
  String get notificationPreviewsTitle => 'メッセージのプレビュー';

  @override
  String get notificationPreviewsDescription => '管理中のノートの通知にメッセージ本文を表示します。';

  @override
  String get notificationPreviewsUpdateFailed => '通知プレビューを更新できませんでした。';

  @override
  String get editNickname => 'ニックネームを編集';

  @override
  String get nicknameLabel => 'ニックネーム';

  @override
  String get nicknameUpdated => 'ニックネームを更新しました。';

  @override
  String nicknameUpdateFailed(Object error) {
    return 'ニックネームを更新できませんでした: $error';
  }

  @override
  String get manageSubscription => 'サブスクリプションを管理';

  @override
  String get upgradeToPro => 'PROにアップグレード';

  @override
  String get proBenefitsSummary => '広告を非表示にし、200件のノートとPRO機能を利用できます';

  @override
  String get subscriptionManagementSummary => 'お支払い・解約・サポート';

  @override
  String get proHeroTitle => '場所の思い出を、もっと自由に';

  @override
  String get proHeroSubtitle => '世界中の場所にノートを残し、振り返り、誰かと共有する楽しみを広げます。';

  @override
  String get proFeatureAdFree => '広告なしで快適に楽しめます';

  @override
  String proFeatureNoteLimit(int count) {
    return '公開中のノートを最大$count件保存できます';
  }

  @override
  String get proFeatureAccessArea => 'より広い範囲から周辺のノートを開けます';

  @override
  String proMonthlyPlan(String price) {
    return '月額 $price';
  }

  @override
  String proYearlyPlan(String price) {
    return '年額 $price';
  }

  @override
  String proIntroOffer(String price) {
    return '初年度 $price';
  }

  @override
  String get proChoosePlan => 'PROプランを選ぶ';

  @override
  String get moderation => 'モデレーション';

  @override
  String get signOut => 'サインアウト';

  @override
  String get followers => 'フォロワー';

  @override
  String get following => 'フォロー中';

  @override
  String subscriptionUnavailableBuild(String planName) {
    return 'このビルドでは$planNameを利用できません。';
  }

  @override
  String subscriptionTemporarilyUnavailable(String planName) {
    return '$planNameは現在利用できません。';
  }
}
