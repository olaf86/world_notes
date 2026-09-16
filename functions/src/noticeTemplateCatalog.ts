/* eslint-disable require-jsdoc */

import {
  Firestore,
  Timestamp,
} from "firebase-admin/firestore";

export const NOTIFICATION_LOCALES = [
  "en",
  "ja",
  "ko",
  "zh-Hans",
  "zh-Hant",
] as const;

export type NotificationLocale = typeof NOTIFICATION_LOCALES[number];

// This template-backed, immutable localized snapshot is the first versioned
// inbox contract. Earlier development documents predate schema versioning.
export const NOTICE_SCHEMA_VERSION = 1;

export const NOTICE_TEMPLATE_IDS = {
  welcome: "welcome",
  newFollower: "newFollower",
  mention: "mention",
  administratorInvitation: "administratorInvitation",
  moderationBan: "moderationBan",
  moderationRestriction: "moderationRestriction",
  moderationWarning: "moderationWarning",
  moderationSensitive: "moderationSensitive",
} as const;

export type NoticeTemplateId =
  typeof NOTICE_TEMPLATE_IDS[keyof typeof NOTICE_TEMPLATE_IDS];

interface LocalizedNoticeCopy {
  readonly title: string;
  readonly body: string;
}

export interface NoticeTemplateDefinition {
  readonly templateId: NoticeTemplateId;
  readonly version: number;
  readonly placeholders: readonly string[];
  readonly localizedContent: Readonly<
    Record<NotificationLocale, LocalizedNoticeCopy>
  >;
}

export interface NoticeTemplateDocument extends NoticeTemplateDefinition {
  readonly updatedAt: Timestamp;
  readonly updatedBy: string;
}

export interface ResolvedNoticeContent {
  readonly locale: NotificationLocale;
  readonly title: string;
  readonly body: string;
}

const TEMPLATE_KEYS = new Set([
  "templateId",
  "version",
  "placeholders",
  "localizedContent",
  "updatedAt",
  "updatedBy",
]);
const LOCALIZED_COPY_KEYS = new Set(["title", "body"]);
const PLACEHOLDER_PATTERN = /\{\{([a-z][A-Za-z0-9]{0,39})\}\}/g;
const MAX_TEMPLATE_ID_LENGTH = 80;
const MAX_TEMPLATE_ARGUMENT_LENGTH = 80;
const MAX_NOTICE_TITLE_LENGTH = 120;
const MAX_NOTICE_BODY_LENGTH = 2000;
const MAX_UPDATED_BY_LENGTH = 200;

export const NOTICE_TEMPLATE_MANIFEST: Readonly<
  Record<NoticeTemplateId, NoticeTemplateDefinition>
> = Object.freeze({
  welcome: template({
    templateId: NOTICE_TEMPLATE_IDS.welcome,
    version: 1,
    placeholders: [],
    localizedContent: {
      "en": {
        title: "Welcome to World Notes",
        body: "In World Notes, you can leave your memories and discoveries " +
          "as notes connected to each place. Explore nearby notes on the " +
          "map and enjoy exchanging messages with people who visit there.",
      },
      "ja": {
        title: "セカイノートへようこそ",
        body: "セカイノートでは、あなたの思い出や発見を、その場所に結びついた" +
          "ノートとして残せます。マップで近くのノートを見つけ、その場所を訪れた" +
          "人たちとのメッセージも楽しんでみましょう。",
      },
      "ko": {
        title: "세계 일기에 오신 것을 환영합니다",
        body: "세계 일기에서는 추억과 발견을 장소에 연결된 노트로 남길 수 " +
          "있습니다. 지도에서 주변 노트를 찾고 그곳을 방문한 사람들과 메시지도 " +
          "나눠 보세요.",
      },
      "zh-Hans": {
        title: "欢迎使用世界日记",
        body: "在世界日记中，你可以把回忆和发现记录为与地点相连的笔记。" +
          "在地图上寻找附近的笔记，也可以和到访同一地点的人交流消息。",
      },
      "zh-Hant": {
        title: "歡迎使用世界日記",
        body: "在世界日記中，你可以把回憶和發現記錄為與地點相連的筆記。" +
          "在地圖上尋找附近的筆記，也可以和造訪同一地點的人交流訊息。",
      },
    },
  }),
  newFollower: template({
    templateId: NOTICE_TEMPLATE_IDS.newFollower,
    version: 1,
    placeholders: ["followerName"],
    localizedContent: {
      "en": {
        title: "New follower",
        body: "{{followerName}} followed you.",
      },
      "ja": {
        title: "新しいフォロワー",
        body: "{{followerName}}さんがあなたをフォローしました。",
      },
      "ko": {
        title: "새 팔로워",
        body: "{{followerName}}님이 회원님을 팔로우했습니다.",
      },
      "zh-Hans": {
        title: "新的关注者",
        body: "{{followerName}} 关注了你。",
      },
      "zh-Hant": {
        title: "新的追蹤者",
        body: "{{followerName}} 追蹤了你。",
      },
    },
  }),
  mention: template({
    templateId: NOTICE_TEMPLATE_IDS.mention,
    version: 1,
    placeholders: ["senderName"],
    localizedContent: {
      "en": {
        title: "{{senderName}} mentioned you",
        body: "View the note location on the map and move closer to read it.",
      },
      "ja": {
        title: "{{senderName}}さんがあなたをメンションしました",
        body: "マップでノートの場所を確認し、近づいて内容を開いてください。",
      },
      "ko": {
        title: "{{senderName}}님이 회원님을 멘션했습니다",
        body: "지도에서 노트 위치를 확인하고 가까이 이동한 후 내용을 열어 보세요.",
      },
      "zh-Hans": {
        title: "{{senderName}} 提及了你",
        body: "请在地图上查看笔记位置，并靠近后打开内容。",
      },
      "zh-Hant": {
        title: "{{senderName}} 提及了你",
        body: "請在地圖上查看筆記位置，並靠近後開啟內容。",
      },
    },
  }),
  administratorInvitation: template({
    templateId: NOTICE_TEMPLATE_IDS.administratorInvitation,
    version: 1,
    placeholders: [],
    localizedContent: {
      "en": {
        title: "Note administrator invitation",
        body: "You have been invited to help administer a note.",
      },
      "ja": {
        title: "ノート管理者への招待",
        body: "ノートの管理を手伝う管理者として招待されました。",
      },
      "ko": {
        title: "노트 관리자 초대",
        body: "노트 관리를 도울 관리자로 초대되었습니다.",
      },
      "zh-Hans": {
        title: "笔记管理员邀请",
        body: "你已受邀协助管理一则笔记。",
      },
      "zh-Hant": {
        title: "筆記管理員邀請",
        body: "你已受邀協助管理一則筆記。",
      },
    },
  }),
  moderationBan: template({
    templateId: NOTICE_TEMPLATE_IDS.moderationBan,
    version: 1,
    placeholders: [],
    localizedContent: {
      "en": {
        title: "Account temporarily banned",
        body: "Your account has been temporarily banned because recent " +
          "posts violated the community safety standards.",
      },
      "ja": {
        title: "アカウントを一時停止しました",
        body: "最近の投稿がコミュニティの安全基準に抵触したため、" +
          "アカウントを一時的に停止しました。",
      },
      "ko": {
        title: "계정이 일시 정지되었습니다",
        body: "최근 게시물이 커뮤니티 안전 기준을 위반하여 계정이 일시 " +
          "정지되었습니다.",
      },
      "zh-Hans": {
        title: "账号已被暂时封禁",
        body: "由于近期发布的内容违反社区安全规范，你的账号已被暂时封禁。",
      },
      "zh-Hant": {
        title: "帳號已被暫時停權",
        body: "由於近期發布的內容違反社群安全規範，你的帳號已被暫時停權。",
      },
    },
  }),
  moderationRestriction: template({
    templateId: NOTICE_TEMPLATE_IDS.moderationRestriction,
    version: 1,
    placeholders: [],
    localizedContent: {
      "en": {
        title: "Posting temporarily restricted",
        body: "Your account is temporarily restricted from posting because " +
          "recent posts violated the community safety standards.",
      },
      "ja": {
        title: "投稿を一時的に制限しました",
        body: "最近の投稿がコミュニティの安全基準に抵触したため、" +
          "投稿機能を一時的に制限しました。",
      },
      "ko": {
        title: "게시가 일시적으로 제한되었습니다",
        body: "최근 게시물이 커뮤니티 안전 기준을 위반하여 게시 기능이 " +
          "일시적으로 제한되었습니다.",
      },
      "zh-Hans": {
        title: "发布功能已被暂时限制",
        body: "由于近期发布的内容违反社区安全规范，你的发布功能已被暂时限制。",
      },
      "zh-Hant": {
        title: "發布功能已被暫時限制",
        body: "由於近期發布的內容違反社群安全規範，你的發布功能已被暫時限制。",
      },
    },
  }),
  moderationWarning: template({
    templateId: NOTICE_TEMPLATE_IDS.moderationWarning,
    version: 1,
    placeholders: [],
    localizedContent: {
      "en": {
        title: "Please review your post",
        body: "One of your posts was hidden or sent to review because it may " +
          "violate the community safety standards. Repeated violations can " +
          "lead to posting restrictions or a ban.",
      },
      "ja": {
        title: "投稿内容をご確認ください",
        body: "投稿のひとつがコミュニティの安全基準に抵触している可能性が" +
          "あるため、非表示または審査対象になりました。違反が繰り返されると、" +
          "投稿制限やアカウント停止の対象になることがあります。",
      },
      "ko": {
        title: "게시물 내용을 확인해 주세요",
        body: "게시물 중 하나가 커뮤니티 안전 기준을 위반했을 가능성이 있어 " +
          "숨김 또는 검토 상태로 전환되었습니다. 위반이 반복되면 게시 제한이나 " +
          "계정 정지로 이어질 수 있습니다.",
      },
      "zh-Hans": {
        title: "请检查你发布的内容",
        body: "你发布的一项内容可能违反社区安全规范，因此已被隐藏或提交审核。" +
          "多次违规可能导致发布受限或账号被封禁。",
      },
      "zh-Hant": {
        title: "請檢查你發布的內容",
        body: "你發布的一項內容可能違反社群安全規範，因此已被隱藏或提交審查。" +
          "多次違規可能導致發布受限或帳號被停權。",
      },
    },
  }),
  moderationSensitive: template({
    templateId: NOTICE_TEMPLATE_IDS.moderationSensitive,
    version: 1,
    placeholders: [],
    localizedContent: {
      "en": {
        title: "Post marked as sensitive",
        body: "One of your posts may contain sensitive content, so it will " +
          "be shown as a sensitive post.",
      },
      "ja": {
        title: "投稿をセンシティブに設定しました",
        body: "投稿のひとつにセンシティブな内容が含まれる可能性があります。" +
          "センシティブな投稿として引き続き表示されます。",
      },
      "ko": {
        title: "게시물이 민감한 콘텐츠로 표시되었습니다",
        body: "게시물 중 하나에 민감한 내용이 포함되었을 수 있어 민감한 " +
          "게시물로 계속 표시됩니다.",
      },
      "zh-Hans": {
        title: "内容已标记为敏感",
        body: "你发布的一项内容可能包含敏感信息，因此会继续以敏感内容形式显示。",
      },
      "zh-Hant": {
        title: "內容已標記為敏感",
        body: "你發布的一項內容可能包含敏感資訊，因此會繼續以敏感內容形式顯示。",
      },
    },
  }),
});

export function notificationLocale(value: unknown): NotificationLocale {
  if (typeof value !== "string") {
    throw new Error("Notification locale is required.");
  }
  const normalized = value.trim().replace(/_/g, "-").toLowerCase();
  switch (normalized) {
  case "en": return "en";
  case "ja": return "ja";
  case "ko": return "ko";
  case "zh-hans": return "zh-Hans";
  case "zh-hant": return "zh-Hant";
  default: throw new Error("Notification locale is unsupported.");
  }
}

export function validateNoticeTemplateDefinition(
  value: unknown,
): NoticeTemplateDefinition {
  const templateValue = requireRecord(value, "template");
  const allowedKeys = new Set([...TEMPLATE_KEYS].filter(
    (key) => key !== "updatedAt" && key !== "updatedBy",
  ));
  requireExactKeys(templateValue, allowedKeys, "template");
  return parseTemplateCore(templateValue);
}

export function parseNoticeTemplateDocument(
  value: unknown,
  expectedTemplateId: string,
): NoticeTemplateDocument {
  const document = requireRecord(value, "template");
  requireExactKeys(document, TEMPLATE_KEYS, "template");
  const template = parseTemplateCore(document);
  if (template.templateId !== expectedTemplateId) {
    throw new Error("Template document ID does not match templateId.");
  }
  if (!(document.updatedAt instanceof Timestamp)) {
    throw new Error("template.updatedAt must be a timestamp.");
  }
  const updatedBy = requireString(
    document.updatedBy,
    "template.updatedBy",
    MAX_UPDATED_BY_LENGTH,
  );
  return Object.freeze({...template, updatedAt: document.updatedAt, updatedBy});
}

export async function resolveNoticeTemplate(
  catalogFirestore: Firestore,
  templateId: NoticeTemplateId,
  locale: NotificationLocale,
  args: Readonly<Record<string, string>> = {},
): Promise<{version: number; content: ResolvedNoticeContent}> {
  const snapshot = await catalogFirestore
    .collection("noticeTemplates")
    .doc(templateId)
    .get();
  if (!snapshot.exists) {
    throw new Error(`Notice template is missing: ${templateId}.`);
  }
  const template = parseNoticeTemplateDocument(snapshot.data(), templateId);
  const content = template.localizedContent[locale];
  const expected = [...template.placeholders].sort();
  const actual = Object.keys(args).sort();
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`Notice template arguments do not match: ${templateId}.`);
  }
  const boundedArgs = Object.fromEntries(Object.entries(args).map(
    ([key, rawValue]) => [
      key,
      requireString(
        rawValue,
        `template argument ${key}`,
        MAX_TEMPLATE_ARGUMENT_LENGTH,
      ),
    ],
  ));
  return {
    version: template.version,
    content: Object.freeze({
      locale,
      title: renderTemplateText(
        content.title,
        boundedArgs,
        MAX_NOTICE_TITLE_LENGTH,
        "title",
      ),
      body: renderTemplateText(
        content.body,
        boundedArgs,
        MAX_NOTICE_BODY_LENGTH,
        "body",
      ),
    }),
  };
}

function template(
  definition: NoticeTemplateDefinition,
): NoticeTemplateDefinition {
  return validateNoticeTemplateDefinition(definition);
}

function parseTemplateCore(
  templateValue: Record<string, unknown>,
): NoticeTemplateDefinition {
  const templateId = requireString(
    templateValue.templateId,
    "template.templateId",
    MAX_TEMPLATE_ID_LENGTH,
  ) as NoticeTemplateId;
  if (!Object.values(NOTICE_TEMPLATE_IDS).includes(templateId)) {
    throw new Error(`Unknown notice template: ${templateId}.`);
  }
  const version = templateValue.version;
  if (!Number.isSafeInteger(version) || (version as number) < 1) {
    throw new Error("template.version must be a positive integer.");
  }
  if (!Array.isArray(templateValue.placeholders) ||
      templateValue.placeholders.some((value) =>
        typeof value !== "string" || !/^[a-z][A-Za-z0-9]{0,39}$/.test(value)
      )) {
    throw new Error("template.placeholders is invalid.");
  }
  const placeholders = [...new Set(templateValue.placeholders as string[])];
  if (placeholders.length !== templateValue.placeholders.length) {
    throw new Error("template.placeholders contains duplicates.");
  }
  const localizedValue = requireRecord(
    templateValue.localizedContent,
    "template.localizedContent",
  );
  requireExactKeys(
    localizedValue,
    new Set(NOTIFICATION_LOCALES),
    "template.localizedContent",
  );
  const localizedContent = Object.fromEntries(NOTIFICATION_LOCALES.map(
    (locale) => {
      const copy = requireRecord(
        localizedValue[locale],
        `template.localizedContent.${locale}`,
      );
      requireExactKeys(
        copy,
        LOCALIZED_COPY_KEYS,
        `template.localizedContent.${locale}`,
      );
      const title = requireString(
        copy.title,
        `template.localizedContent.${locale}.title`,
        MAX_NOTICE_TITLE_LENGTH,
      );
      const body = requireString(
        copy.body,
        `template.localizedContent.${locale}.body`,
        MAX_NOTICE_BODY_LENGTH,
      );
      const found = new Set([...title.matchAll(PLACEHOLDER_PATTERN),
        ...body.matchAll(PLACEHOLDER_PATTERN)].map((match) => match[1]));
      if (JSON.stringify([...found].sort()) !==
          JSON.stringify([...placeholders].sort())) {
        throw new Error(`Template placeholders differ for locale ${locale}.`);
      }
      return [locale, Object.freeze({title, body})];
    },
  )) as Record<NotificationLocale, LocalizedNoticeCopy>;
  return Object.freeze({
    templateId,
    version: version as number,
    placeholders: Object.freeze(placeholders),
    localizedContent: Object.freeze(localizedContent),
  });
}

function renderTemplateText(
  source: string,
  args: Readonly<Record<string, string>>,
  maxLength: number,
  field: string,
): string {
  const rendered = source.replace(PLACEHOLDER_PATTERN, (_, key: string) =>
    args[key] ?? "",
  ).trim();
  if (rendered.length === 0 || rendered.length > maxLength) {
    throw new Error(`Resolved notice ${field} is outside its size limit.`);
  }
  return rendered;
}

function requireRecord(
  value: unknown,
  path: string,
): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new Error(`${path} must be an object.`);
  }
  return value as Record<string, unknown>;
}

function requireExactKeys(
  value: Record<string, unknown>,
  keys: ReadonlySet<string>,
  path: string,
): void {
  const actual = Object.keys(value);
  if (actual.length !== keys.size || actual.some((key) => !keys.has(key))) {
    throw new Error(`${path} has unexpected fields.`);
  }
}

function requireString(
  value: unknown,
  path: string,
  maxLength: number,
): string {
  if (typeof value !== "string") throw new Error(`${path} must be a string.`);
  const normalized = value.trim();
  if (normalized.length === 0 || normalized.length > maxLength) {
    throw new Error(`${path} is outside its size limit.`);
  }
  return normalized;
}
