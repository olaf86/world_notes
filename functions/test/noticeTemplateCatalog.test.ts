/* eslint-disable require-jsdoc */

import assert from "node:assert/strict";
import test from "node:test";

import {Firestore, Timestamp} from "firebase-admin/firestore";

import {
  NOTICE_SCHEMA_VERSION,
  NOTICE_TEMPLATE_IDS,
  NOTICE_TEMPLATE_MANIFEST,
  NOTIFICATION_LOCALES,
  notificationLocale,
  resolveNoticeTemplate,
  validateNoticeTemplateDefinition,
} from "../src/noticeTemplateCatalog";

test("manifest validates every template and app locale", () => {
  assert.equal(NOTICE_SCHEMA_VERSION, 2);
  for (const definition of Object.values(NOTICE_TEMPLATE_MANIFEST)) {
    assert.equal(
      validateNoticeTemplateDefinition(definition).templateId,
      definition.templateId,
    );
    assert.deepEqual(
      Object.keys(definition.localizedContent).sort(),
      [...NOTIFICATION_LOCALES].sort(),
    );
  }
});

test("moderation copy uses safety standards and explicit labels", () => {
  const warning = NOTICE_TEMPLATE_MANIFEST.moderationWarning.localizedContent;
  const sensitive = NOTICE_TEMPLATE_MANIFEST.moderationSensitive
    .localizedContent;

  assert.match(warning.ja.body, /コミュニティの安全基準/);
  assert.doesNotMatch(warning.ja.body, /ポリシー/);
  assert.equal(sensitive.ja.title, "投稿をセンシティブに設定しました");
  assert.match(sensitive.en.title, /marked as sensitive/);
  assert.match(sensitive.ko.title, /표시되었습니다/);
  assert.match(sensitive["zh-Hans"].title, /标记为敏感/);
  assert.match(sensitive["zh-Hant"].title, /標記為敏感/);
});

test("notification locale normalizes supported Chinese tags", () => {
  assert.equal(notificationLocale("zh_Hans"), "zh-Hans");
  assert.equal(notificationLocale("zh-hant"), "zh-Hant");
  assert.throws(() => notificationLocale("system"), /unsupported/);
});

test("runtime resolves a version and bounded arguments", async () => {
  const definition = NOTICE_TEMPLATE_MANIFEST.mention;
  const result = await resolveNoticeTemplate(
    templateFirestore({
      ...definition,
      placeholders: [...definition.placeholders],
      localizedContent: {...definition.localizedContent},
      updatedAt: Timestamp.fromMillis(1_000),
      updatedBy: "test",
    }),
    NOTICE_TEMPLATE_IDS.mention,
    "ja",
    {senderName: "Alex"},
  );

  assert.equal(result.version, 1);
  assert.equal(result.content.locale, "ja");
  assert.equal(result.content.title, "Alexさんがあなたをメンションしました");
});

test("runtime resolution rejects missing or unexpected arguments", async () => {
  const definition = NOTICE_TEMPLATE_MANIFEST.newFollower;
  const firestore = templateFirestore({
    ...definition,
    placeholders: [...definition.placeholders],
    localizedContent: {...definition.localizedContent},
    updatedAt: Timestamp.fromMillis(1_000),
    updatedBy: "test",
  });

  await assert.rejects(
    resolveNoticeTemplate(
      firestore,
      NOTICE_TEMPLATE_IDS.newFollower,
      "en",
    ),
    /arguments do not match/,
  );
});

function templateFirestore(data: unknown): Firestore {
  return {
    collection: () => ({
      doc: () => ({
        get: async () => ({exists: true, data: () => data}),
      }),
    }),
  } as unknown as Firestore;
}
