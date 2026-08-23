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
  String get noNotifications => '通知はまだありません。';

  @override
  String get noFollowers => 'フォロワーはまだいません。';

  @override
  String get noFollowing => 'まだ誰もフォローしていません。';

  @override
  String get noFootprints => '足あとはまだありません。';

  @override
  String get noFootprintsDescription => '訪問者がこのノートを開くと、ここに表示されます。';

  @override
  String get noAccessMembers => 'アクセスできるユーザーはまだいません。リンクを共有して追加してください。';

  @override
  String get noModerationReviews => 'レビューはありません。';

  @override
  String get youLabel => 'あなた';

  @override
  String get messageSending => '送信中…';

  @override
  String messageScheduledAt(String time) {
    return '$timeに公開予定';
  }

  @override
  String get reportMessageAction => 'メッセージを通報';

  @override
  String get reportNoteAction => 'ノートを通報';

  @override
  String get reportMessageTitle => 'メッセージを通報';

  @override
  String get reportNoteTitle => 'ノートを通報';

  @override
  String get reportMessageQuestion => 'このメッセージを通報する理由を選んでください';

  @override
  String get reportNoteQuestion => 'このノートを通報する理由を選んでください';

  @override
  String get reportReasonSpam => 'スパムまたは広告';

  @override
  String get reportReasonHarassment => '嫌がらせまたはいじめ';

  @override
  String get reportReasonSexual => '成人向けまたは露骨なコンテンツ';

  @override
  String get reportReasonIllegal => '違法なコンテンツ';

  @override
  String get reportReasonOther => 'その他';

  @override
  String get reportMessagePrivacy =>
      'あなたのユーザーID、このメッセージID、ノートID、選択した理由が確認のため管理者に共有されます。';

  @override
  String get reportNotePrivacy => 'あなたのユーザーID、このノートID、選択した理由が確認のため管理者に共有されます。';

  @override
  String get reportSubmitting => '送信中…';

  @override
  String get reportSubmitAction => '通報を送信';

  @override
  String get reportSubmitted => '通報を受け付けました。コミュニティの安全維持にご協力いただきありがとうございます。';

  @override
  String get reportAlsoBlockUser => 'このユーザーもブロックする';

  @override
  String get reportAlsoBlockUserDescription =>
      '通報後、このユーザーのノートとメッセージは表示されなくなります。';

  @override
  String get reportSubmittedBlockFailed => '通報は完了しましたが、ユーザーをブロックできませんでした。';

  @override
  String reportFailed(Object error) {
    return '通報を送信できませんでした: $error';
  }

  @override
  String get reportCooldown => '少し時間をおいてから、もう一度通報してください。';

  @override
  String get reportUnavailable => 'このコンテンツは現在通報できません。';

  @override
  String get contentModerationUnavailable => '安全性の確認を一時的に利用できません。もう一度お試しください。';

  @override
  String get contentNotAllowed => 'この内容は公開できません。内容を修正して、もう一度お試しください。';

  @override
  String get imageNotAllowed => 'この画像は使用できません。別の画像を選択してください。';

  @override
  String get noteCreatedPinImageUploadFailed =>
      'ノートは作成されましたが、ピン画像をアップロードできませんでした。';

  @override
  String get noteCreateNetworkError => 'サーバーに接続できませんでした。通信状態を確認して、もう一度お試しください。';

  @override
  String get noteCreateAuthenticationRequired => 'ノートを作成するには、もう一度サインインしてください。';

  @override
  String get noteCreateFailed => 'ノートを作成できませんでした。もう一度お試しください。';

  @override
  String get noteCreateUnexpectedError => '予期しないエラーが発生しました。もう一度お試しください。';

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
  String get useLock => 'ロックを使用';

  @override
  String get updateAction => '更新';

  @override
  String get confirmPasswordLabel => 'パスワード（確認）';

  @override
  String get patternSetupInstruction => '隣り合う点をつないでパターンを描いてください。';

  @override
  String get lockHintOptional => 'ヒント（任意）';

  @override
  String get clearAction => 'クリア';

  @override
  String get passwordRequired => 'パスワードを入力してください。';

  @override
  String passwordMaxLength(int maxLength) {
    return 'パスワードは$maxLength文字以内で入力してください。';
  }

  @override
  String get passwordConfirmationRequired => '確認のためパスワードをもう一度入力してください。';

  @override
  String get passwordsDoNotMatch => 'パスワードが一致しません。';

  @override
  String get patternRequired => 'ノートをロックするパターンを描いてください。';

  @override
  String patternTooLong(int maxLength) {
    return 'パターンが長すぎます。$maxLength個以下の点を使用してください。';
  }

  @override
  String get patternInvalidNode => 'パターンに無効な点が含まれています。';

  @override
  String get patternNeighboringOnly => 'パターンは隣り合う点のみ接続できます。';

  @override
  String get lockSavedPrivate => 'ロックを保存しました。このノートは非公開です。';

  @override
  String get lockSaveFailed => 'ロックを保存できませんでした。';

  @override
  String get appVerificationFailed => 'このアプリを確認できませんでした。もう一度お試しください。';

  @override
  String get authenticationExpired => '認証に失敗しました。もう一度サインインしてください。';

  @override
  String get lockCreatorOnly => 'ロックを変更できるのはノートの作成者だけです。';

  @override
  String get noteNotFound => 'ノートが見つかりません。';

  @override
  String get incorrectPattern => 'パターンが正しくありません。';

  @override
  String get incorrectPassword => 'パスワードが正しくありません。';

  @override
  String get tooManyAttempts => '試行回数が多すぎます。しばらくしてからもう一度お試しください。';

  @override
  String get noteUnlockFailed => 'このノートのロックを解除できませんでした。';

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
  String get blockUserAction => 'ユーザーをブロック';

  @override
  String get unblockUserAction => 'ブロックを解除';

  @override
  String blockUserTitle(String name) {
    return '$nameさんをブロックしますか？';
  }

  @override
  String get blockUserConfirmation =>
      'このユーザーのノートとメッセージは表示されなくなります。お互いのフォローは解除され、あなたが所有するノートへのアクセスも取り消されます。第三者が所有するノートでは、引き続き同じ場所に参加する場合があります。';

  @override
  String get blockUserConfirmAction => 'ブロック';

  @override
  String unblockUserTitle(String name) {
    return '$nameさんのブロックを解除しますか？';
  }

  @override
  String get unblockUserConfirmation =>
      'このユーザーのコンテンツが再び表示されるようになります。以前のフォローや、あなたのノートへのアクセスは復元されません。';

  @override
  String userBlocked(String name) {
    return '$nameさんをブロックしました。';
  }

  @override
  String userUnblocked(String name) {
    return '$nameさんのブロックを解除しました。';
  }

  @override
  String updateUserBlockFailed(Object error) {
    return 'ブロック設定を更新できませんでした: $error';
  }

  @override
  String get settingsTitle => '設定';

  @override
  String get blockedUsersTitle => 'ブロックしたユーザー';

  @override
  String get blockedUsersDescription => 'ブロックしたユーザーの確認と解除';

  @override
  String get noBlockedUsers => 'ブロックしているユーザーはいません。';

  @override
  String blockedUsersLoadFailed(Object error) {
    return 'ブロックしたユーザーを読み込めませんでした: $error';
  }

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
  String get settingsContentWorldTitle => 'コンテンツワールド';

  @override
  String get settingsContentWorldDescription =>
      '閲覧・投稿するワールドを選びます。変更できないホームワールドはそのままです。';

  @override
  String get settingsContentWorldSwitchFailed =>
      'ワールドを切り替えられませんでした。もう一度お試しください。';

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
  String get homeWorldSelectionTitle => 'ホームワールドを選択';

  @override
  String get homeWorldSelectionIntro => 'ホームワールドは、あなたのアカウントデータを身近な地域に保管する場所です。';

  @override
  String get homeWorldSelectionPermanentWarning =>
      'この選択は後から変更できません。ホームを移動せずに、準備済みのほかのワールドを訪れることはできます。';

  @override
  String get homeWorldSelectionUnavailable => '現在選択できるホームワールドはありません。';

  @override
  String get homeWorldSelectionLoadFailed => 'アカウントの準備状況を読み込めませんでした。';

  @override
  String get homeWorldSelectionSubmitFailed =>
      'ホームワールドを設定できませんでした。もう一度お試しください。';

  @override
  String get homeWorldSelectionConfirm => 'このワールドを変更できないホームに設定';

  @override
  String get worldAsia => 'アジア';

  @override
  String get worldAsiaLocation => '日本・東京';

  @override
  String get worldNorthAmerica => '北米';

  @override
  String get worldNorthAmericaLocation => 'アメリカ・アイオワ';

  @override
  String get worldEurope => 'ヨーロッパ';

  @override
  String get worldEuropeLocation => 'ベルギー';

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

  @override
  String get adminAccountSafety => 'アカウント安全性';

  @override
  String get adminSafetyTargetUid => '対象ユーザーID';

  @override
  String get adminSafetyLoad => 'アカウント安全性を読み込む';

  @override
  String get adminSafetyPoints => '違反ポイント';

  @override
  String get adminSafetyAuthorityWorld => '正本ワールド';

  @override
  String get adminSafetyRestriction => '投稿制限';

  @override
  String get adminSafetyBan => 'BAN';

  @override
  String get adminSafetyNone => 'なし';

  @override
  String get adminSafetyPermanent => '永久';

  @override
  String get adminSafetyAdjustPoints => 'ポイントを調整';

  @override
  String get adminSafetyPointDelta => 'ポイント増減値';

  @override
  String get adminSafetyPointDeltaHelp => '0を除く-100から100の整数を入力してください。';

  @override
  String adminSafetySetRestriction(int days) {
    return '$days日間の投稿制限';
  }

  @override
  String get adminSafetyClearRestriction => '投稿制限を解除';

  @override
  String adminSafetySetBan(int days) {
    return '$days日間BAN';
  }

  @override
  String get adminSafetySetPermanentBan => '永久BAN';

  @override
  String get adminSafetyClearBan => 'BANを解除';

  @override
  String get adminSafetyReason => '理由（必須）';

  @override
  String get adminSafetyReference => 'レビュー・サポート参照（任意）';

  @override
  String get adminSafetyApply => '適用';

  @override
  String get adminSafetyContinue => '続ける';

  @override
  String get adminSafetyAccepted => '処理を受け付けました。バックグラウンドで継続します。';

  @override
  String get adminSafetyAuditHistory => '管理者操作履歴';

  @override
  String get adminSafetyNoAudits => '管理者操作はありません。';

  @override
  String get administratorInvitationTitle => 'ノート管理者への招待';

  @override
  String get inviteLoadFailed => 'この招待を読み込めませんでした。';

  @override
  String get inviteAcceptFailed => 'この招待を承認できませんでした。';

  @override
  String get worldStillPreparing => 'このワールドではアカウントを準備中です。';

  @override
  String get inviteInvalid => 'この招待は無効か、すでに利用できません。';

  @override
  String get inviteExpired => 'この招待は期限切れです。';

  @override
  String get networkErrorTryAgain => 'ネットワークエラーです。接続を確認してもう一度お試しください。';

  @override
  String get inviteSignInPrompt => 'ノート管理者への招待を確認するにはサインインしてください。';

  @override
  String get signIn => 'サインイン';

  @override
  String get administratorInvitationAccepted =>
      'ノート管理者になりました。ホームワールドは変更されていません。';

  @override
  String get switchWorldAndOpenNote => 'ワールドを切り替えてノートを開く';

  @override
  String get goToMap => 'マップへ移動';

  @override
  String get administratorInvitationExplanation =>
      '承認すると、現在地に関係なくこのノートの閲覧と管理ができます。投稿、いいね、訪問には通常の位置情報ルールが適用されます。';

  @override
  String get switchWorldAfterAcceptance => '承認後にこのワールドへ切り替える';

  @override
  String get acceptAdministratorInvitation => '管理者への招待を承認';

  @override
  String get administratorManageDescription =>
      '特定のユーザーを、このノートの管理者として招待します。管理者権限だけでは遠隔地から通常の投稿はできません。';

  @override
  String get targetUserIdLabel => '招待するユーザーID';

  @override
  String get sendAdministratorInvitation => '管理者として招待';

  @override
  String get administratorInviteCreated => '管理者への招待を作成しました。';

  @override
  String get inviteCreateFailed => '招待を作成できませんでした。';

  @override
  String get administratorInviteRevoked => '管理者への招待を取り消しました。';

  @override
  String get inviteRevokeFailed => '招待を取り消せませんでした。';

  @override
  String get administratorRemoved => '管理者権限を削除しました。';

  @override
  String get administratorRemoveFailed => '管理者権限を削除できませんでした。';

  @override
  String get memberRemoveFailed => 'このメンバーを削除できませんでした。';

  @override
  String get copyLink => 'リンクをコピー';

  @override
  String get copied => 'コピーしました';

  @override
  String get noteAdministratorsTitle => 'ノート管理者';

  @override
  String get pendingAdministratorInvitationsTitle => '承認待ちの招待';

  @override
  String get passwordAccessMembersTitle => 'パスワードでのアクセス';

  @override
  String get passwordAccessDescription => '現在のパスワードで非公開ノートを解除したユーザーです。';

  @override
  String get unlockedWithPassword => 'パスワードで解除';

  @override
  String get removeAccess => 'アクセス権を削除';

  @override
  String get noteCreatorLabel => '作成者';

  @override
  String get noteAdministratorLabel => '管理者';

  @override
  String get resignAdministrator => '管理者を辞任';

  @override
  String get removeAdministrator => '管理者から削除';

  @override
  String get noPendingInvitations => '承認待ちの招待はありません。';

  @override
  String get invitationPending => '承認待ち';

  @override
  String get revokeInvitation => '招待を取り消す';

  @override
  String get authEmailAlreadyRegistered => 'このメールアドレスはすでに登録されています。';

  @override
  String get invalidEmail => '有効なメールアドレスを入力してください。';

  @override
  String get authInvalidCredentials => 'メールアドレスまたはパスワードが正しくありません。';

  @override
  String get authOperationNotAllowed => '現在、メールアドレスとパスワードでのサインインは利用できません。';

  @override
  String get authWeakPassword => 'より安全なパスワードを設定してください。';

  @override
  String get authFailed => '認証に失敗しました。もう一度お試しください。';

  @override
  String get authTagline => '世界のひとコマを、ひとつのノートに';

  @override
  String get emailLabel => 'メールアドレス';

  @override
  String get requiredField => '必須項目です';

  @override
  String minimumPasswordLength(int count) {
    return '$count文字以上で入力してください。';
  }

  @override
  String get createAccount => 'アカウントを作成';

  @override
  String get alreadyHaveAccountSignIn => 'アカウントをお持ちですか？ サインイン';

  @override
  String get newHereCreateAccount => '初めてですか？ アカウントを作成';

  @override
  String get orDivider => 'または';

  @override
  String get continueWithGoogle => 'Googleで続ける';

  @override
  String get continueWithApple => 'Appleで続ける';

  @override
  String get accountSettingsTitle => 'アカウント';

  @override
  String get deleteAccountTitle => 'アカウントを削除';

  @override
  String get deleteAccountDescription => 'アカウントと関連データを完全に削除します。';

  @override
  String get deleteAccountWarning =>
      'あなたのプロフィールや投稿に加え、あなたが作成したノート全体（他の管理者の権限と、参加者が投稿したメッセージ・画像を含む）を、セカイノートの全地域から完全に削除します。この操作は取り消せません。';

  @override
  String get deleteAccountSubscriptionWarning =>
      'セカイノートのアカウントを削除してもApp Storeのサブスクリプションは解約されません。今後の請求を防ぐため、削除前に有効なサブスクリプションを解約してください。';

  @override
  String get currentPasswordLabel => '現在のパスワード';

  @override
  String get deleteAccountConfirm => '完全に削除';

  @override
  String get deleteAccountFailed => 'アカウントを削除できませんでした。サインインを確認して、もう一度お試しください。';

  @override
  String get webpUnsupported => 'この端末では画像のエンコードに対応していません。';

  @override
  String messageImageUploadFailed(Object error) {
    return '画像をアップロードできませんでした: $error';
  }

  @override
  String messageSendFailed(Object error) {
    return 'メッセージを送信できませんでした: $error';
  }

  @override
  String get messageContentHint => 'この場所で何がありましたか？';

  @override
  String get newMessageTitle => '新しいメッセージ';

  @override
  String get sendAction => '送信';

  @override
  String get chooseFromLibrary => 'ライブラリから選択';

  @override
  String get takePhoto => '写真を撮る';

  @override
  String get postTime => '投稿日時';

  @override
  String get thumbnailRenderFailed => 'サムネイルのプレビューを作成できませんでした。';

  @override
  String get mapPinImageTitle => 'マップピンの画像';

  @override
  String get mapPinCropInstruction => 'ドラッグやピンチ操作でピンに表示する範囲を選んでください。';

  @override
  String get zoomOut => '縮小';

  @override
  String get zoomIn => '拡大';

  @override
  String get resetAction => 'リセット';

  @override
  String get useImageAction => 'この画像を使用';

  @override
  String pinImagePreparationFailed(Object error) {
    return 'ピン画像を準備できませんでした: $error';
  }

  @override
  String get closeAction => '閉じる';

  @override
  String notificationsLoadFailed(Object error) {
    return 'お知らせを読み込めませんでした: $error';
  }

  @override
  String get adPrivacyTitle => '広告のプライバシー';

  @override
  String get managePrivacyChoices => 'プライバシー設定を管理';

  @override
  String get managePrivacyChoicesDescription => '広告での情報の利用方法を確認または変更します。';

  @override
  String privacyChoicesOpenFailed(Object error) {
    return 'プライバシー設定を開けませんでした: $error';
  }

  @override
  String get followUpdateFailed => 'フォロー設定を更新できませんでした。';

  @override
  String profileLoadFailed(Object error) {
    return 'プロフィールを読み込めませんでした: $error';
  }

  @override
  String get profileNotFound => 'プロフィールが見つかりません。';

  @override
  String followUnavailable(Object error) {
    return 'フォローを利用できません: $error';
  }

  @override
  String get followAction => 'フォロー';

  @override
  String get unfollowAction => 'フォロー解除';

  @override
  String followListLoadFailed(Object error) {
    return '一覧を読み込めませんでした: $error';
  }

  @override
  String followerCountLabel(int count) {
    return '$count人のフォロワー';
  }

  @override
  String get footprintsUpdateFailed => '足あと設定を更新できませんでした。';

  @override
  String get footprintsTitle => '足あと';

  @override
  String get sortLatest => '新しい順';

  @override
  String get visitsLabel => '訪問回数';

  @override
  String footprintsLoadFailed(Object error) {
    return '足あとを読み込めませんでした: $error';
  }

  @override
  String get newVisitsNotRecorded => '新しい訪問は記録されません';

  @override
  String visitCountLabel(int count) {
    return '$count回訪問';
  }

  @override
  String get cannotWriteHere => 'ここには投稿できません。';

  @override
  String get cancelScheduledMessageTitle => '予約メッセージを取り消す';

  @override
  String get deleteMessageTitle => 'メッセージを削除';

  @override
  String get cancelScheduledMessageConfirmation =>
      'この予約メッセージを取り消しますか？ 確保されていた枠は解放されます。';

  @override
  String get deleteMessageConfirmation =>
      'このメッセージを削除しますか？ すべてのユーザーに削除済みとして表示されます。';

  @override
  String get cancelMessageAction => 'メッセージを取り消す';

  @override
  String get deleteAction => '削除';

  @override
  String messageDeleteFailed(Object error) {
    return 'メッセージを削除できませんでした: $error';
  }

  @override
  String get threadCloseTitle => 'スレッドを終了しますか？';

  @override
  String get threadCloseConfirmation =>
      '終了すると新しいメッセージは投稿できません。既存のメッセージは引き続き閲覧でき、あとで再開できます。';

  @override
  String threadCloseFailed(Object error) {
    return 'スレッドを終了できませんでした: $error';
  }

  @override
  String threadReopenFailed(Object error) {
    return 'スレッドを再開できませんでした: $error';
  }

  @override
  String get themeChangeFailed => 'テーマを変更できませんでした。';

  @override
  String viewUserProfile(String name) {
    return '$nameさんのプロフィールを表示';
  }

  @override
  String get showFewerColors => '色を少なく表示';

  @override
  String get showMoreColors => '色をもっと表示';

  @override
  String get colorGreen => '緑';

  @override
  String get colorBlue => '青';

  @override
  String get colorRed => '赤';

  @override
  String get colorOrange => 'オレンジ';

  @override
  String get colorPurple => '紫';

  @override
  String get colorTeal => 'ティール';

  @override
  String get colorPink => 'ピンク';

  @override
  String get colorBrown => '茶色';

  @override
  String get colorIndigo => '藍色';

  @override
  String get colorCyan => 'シアン';

  @override
  String get colorLime => 'ライム';

  @override
  String get colorAmber => 'アンバー';

  @override
  String get colorDeepOrange => '濃いオレンジ';

  @override
  String get colorBlueGrey => 'ブルーグレー';

  @override
  String get messageRemovedByAdministrator => 'このメッセージは管理者によって削除されました。';

  @override
  String get messageDeleted => 'このメッセージは削除されました。';

  @override
  String get sensitiveContent => 'センシティブな内容';

  @override
  String get sensitiveMessageWarning => 'このメッセージにはセンシティブな内容が含まれている可能性があります。';

  @override
  String get showAnywayAction => '表示する';

  @override
  String get scheduledMessage => '予約メッセージ';

  @override
  String get scheduledLabel => '予約済み';

  @override
  String get likeMessage => 'メッセージにいいね';

  @override
  String get unlikeMessage => 'メッセージのいいねを解除';

  @override
  String get showFewerIcons => 'アイコンを少なく表示';

  @override
  String get showMoreIcons => 'アイコンをもっと表示';

  @override
  String get pinIconPlace => '場所';

  @override
  String get pinIconRestaurant => 'レストラン';

  @override
  String get pinIconPark => '公園';

  @override
  String get pinIconHome => '家';

  @override
  String get pinIconStar => '星';

  @override
  String get pinIconPhoto => '写真';

  @override
  String get pinIconMusic => '音楽';

  @override
  String get pinIconCoffee => 'コーヒー';

  @override
  String get pinIconShopping => 'ショッピング';

  @override
  String get pinIconHotel => 'ホテル';

  @override
  String get pinIconDirections => '車';

  @override
  String get pinIconHiking => 'ハイキング';

  @override
  String get pinIconPets => 'ペット';

  @override
  String get pinIconWork => '仕事';

  @override
  String get pinIconFavorite => 'お気に入り';

  @override
  String get mapNotesLoadFailed => '周辺のノートを読み込めませんでした。もう一度お試しください。';

  @override
  String get mapNotesRefreshFailed => '周辺のノートを更新できませんでした。もう一度お試しください。';

  @override
  String get mapNoteOpenFailedNearby => 'ノートを開けませんでした。近くに移動してもう一度お試しください。';

  @override
  String get commonRefresh => '更新';

  @override
  String get adminAccessRequired => '管理者権限が必要です。';

  @override
  String get moderationOpen => '未対応';

  @override
  String get moderationResolved => '対応済み';

  @override
  String moderationMarkedAs(String action) {
    return '$actionに設定しました。';
  }

  @override
  String get reasonLabel => '理由';

  @override
  String get applyAction => '適用';

  @override
  String get emptyContent => '（内容なし）';

  @override
  String reportCount(int count) {
    return '通報$count件';
  }

  @override
  String get moderationAllowAction => '許可';

  @override
  String get moderationSensitiveAction => 'センシティブ';

  @override
  String get moderationHideAction => '非表示';

  @override
  String get moderationAllowedStatus => '許可済み';

  @override
  String get moderationSensitiveStatus => 'センシティブ';

  @override
  String get moderationHiddenStatus => '非表示';

  @override
  String get moderationAllowTitle => 'メッセージを許可';

  @override
  String get moderationSensitiveTitle => 'センシティブに設定';

  @override
  String get moderationHideTitle => 'メッセージを非表示';
}
