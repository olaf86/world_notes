// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

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
      'World Notes を楽しむために、現在位置のトラッキング許可を有効にしてください。';

  @override
  String get locationPermissionOpenSettings => '設定を開く';

  @override
  String get locationPermissionAllow => '現在位置を許可';

  @override
  String get locationServiceDisabledTitle => '位置情報サービスをオンにしてください';

  @override
  String get locationServiceDisabledMessage =>
      'World Notes を利用するには、端末の位置情報サービスをオンにしてください。';

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
