/* eslint-disable require-jsdoc, no-console */

import {deleteApp, initializeApp} from "firebase-admin/app";
import {FieldValue} from "firebase-admin/firestore";

import {
  NOTICE_TEMPLATE_MANIFEST,
  NoticeTemplateDefinition,
  parseNoticeTemplateDocument,
  validateNoticeTemplateDefinition,
} from "../noticeTemplateCatalog";
import {
  createAdminWorldFirestoreClient,
  DEFAULT_FIRESTORE_DATABASE_ID,
} from "../platform/worldFirestoreProvider";

const PROJECT_PATTERN = /^[a-z][a-z0-9-]{4,28}[a-z0-9]$/;

interface ParsedArgs {
  readonly projectId: string;
  readonly actor: string;
  readonly apply: boolean;
}

function usage(): string {
  return [
    "Usage:",
    "  npm run templates:notices -- --project <id> --actor <operator-id>",
    "  npm run templates:notices -- --project <id> --actor <operator-id> \\",
    "    --apply --confirm-project <id>",
    "",
    "Default mode validates only and performs no Firestore writes.",
  ].join("\n");
}

function parseArgs(argv: string[]): ParsedArgs {
  let projectId: string | undefined;
  let actor: string | undefined;
  let apply = false;
  let confirmProject: string | undefined;
  for (let index = 0; index < argv.length; index++) {
    const arg = argv[index];
    if (arg === "--project") {
      projectId = argv[index + 1]?.trim();
      index++;
    } else if (arg === "--actor") {
      actor = argv[index + 1]?.trim();
      index++;
    } else if (arg === "--apply") {
      apply = true;
    } else if (arg === "--confirm-project") {
      confirmProject = argv[index + 1]?.trim();
      index++;
    } else {
      throw new Error(`Unknown argument: ${arg}\n\n${usage()}`);
    }
  }
  if (projectId === undefined || !PROJECT_PATTERN.test(projectId)) {
    throw new Error("--project is required and invalid.\n\n" + usage());
  }
  if (actor === undefined || actor.length === 0 || actor.length > 200) {
    throw new Error(
      "--actor is required and must be at most 200 characters.\n\n" + usage(),
    );
  }
  if (apply && confirmProject !== projectId) {
    throw new Error(
      "Apply requires --confirm-project to exactly match --project.",
    );
  }
  if (!apply && confirmProject !== undefined) {
    throw new Error("--confirm-project is accepted only with --apply.");
  }
  return {projectId, actor, apply};
}

function sameDefinition(
  left: NoticeTemplateDefinition,
  right: NoticeTemplateDefinition,
): boolean {
  const comparable = (value: NoticeTemplateDefinition) => ({
    templateId: value.templateId,
    version: value.version,
    placeholders: [...value.placeholders],
    localizedContent: value.localizedContent,
  });
  return JSON.stringify(comparable(left)) === JSON.stringify(comparable(right));
}

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));
  const definitions = Object.values(NOTICE_TEMPLATE_MANIFEST).map(
    validateNoticeTemplateDefinition,
  );
  console.log(`Validated ${definitions.length} notice templates.`);
  if (!args.apply) {
    for (const definition of definitions) {
      console.log(`${definition.templateId}: v${definition.version}`);
    }
    console.log("Dry run complete; no Firestore writes were performed.");
    return;
  }

  const app = initializeApp({projectId: args.projectId});
  const firestore = createAdminWorldFirestoreClient(
    app,
    DEFAULT_FIRESTORE_DATABASE_ID,
  );
  try {
    const updates = await firestore.runTransaction(async (transaction) => {
      const references = definitions.map((definition) =>
        firestore.collection("noticeTemplates").doc(definition.templateId)
      );
      const snapshots = await transaction.getAll(...references);
      const changed: string[] = [];
      snapshots.forEach((snapshot, index) => {
        const definition = definitions[index];
        if (snapshot.exists) {
          const current = parseNoticeTemplateDocument(
            snapshot.data(),
            definition.templateId,
          );
          if (current.version === definition.version) {
            if (!sameDefinition(current, definition)) {
              throw new Error(
                `${definition.templateId} changed without incrementing ` +
                "version.",
              );
            }
            return;
          }
          if (definition.version !== current.version + 1) {
            throw new Error(
              `${definition.templateId} must advance from ` +
              `v${current.version} ` +
              `to v${current.version + 1}.`,
            );
          }
        } else if (definition.version !== 1) {
          throw new Error(
            `${definition.templateId} must start at version 1.`,
          );
        }

        transaction.set(references[index], {
          ...definition,
          placeholders: [...definition.placeholders],
          localizedContent: {...definition.localizedContent},
          updatedAt: FieldValue.serverTimestamp(),
          updatedBy: args.actor,
        });
        changed.push(`${definition.templateId}: v${definition.version}`);
      });
      return changed;
    });

    if (updates.length === 0) {
      console.log("Notice template catalog is already current.");
    } else {
      console.log("Updated notice templates:");
      updates.forEach((value) => console.log(`  ${value}`));
    }
    console.log(`projectId: ${args.projectId}`);
    console.log(`databaseId: ${DEFAULT_FIRESTORE_DATABASE_ID}`);
    console.log(`actor: ${args.actor}`);
  } finally {
    await firestore.terminate();
    await deleteApp(app);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
