/* eslint-disable require-jsdoc, no-console */
import {deleteApp, initializeApp} from "firebase-admin/app";
import {getAuth, UserRecord} from "firebase-admin/auth";

const projectId = process.env.GCLOUD_PROJECT || "world-notes-prod";
const app = initializeApp({projectId});
const auth = getAuth(app);

interface ParsedArgs {
  uid?: string;
  email?: string;
  admin: boolean;
}

function usage(): string {
  return [
    "Usage:",
    "  npm run admin:set -- --uid <uid>",
    "  npm run admin:set -- --email <email>",
    "  npm run admin:unset -- --uid <uid>",
    "  npm run admin:unset -- --email <email>",
    "",
    "Set GCLOUD_PROJECT to target a non-production project.",
  ].join("\n");
}

function parseArgs(argv: string[]): ParsedArgs {
  const args: ParsedArgs = {
    admin: !argv.includes("--unset"),
  };
  for (let index = 0; index < argv.length; index++) {
    const arg = argv[index];
    if (arg === "--uid") {
      args.uid = argv[index + 1];
      index++;
    } else if (arg === "--email") {
      args.email = argv[index + 1];
      index++;
    } else if (arg === "--unset") {
      args.admin = false;
    } else {
      throw new Error(`Unknown argument: ${arg}\n\n${usage()}`);
    }
  }
  if ((args.uid == null) === (args.email == null)) {
    throw new Error(`Specify exactly one of --uid or --email.\n\n${usage()}`);
  }
  return args;
}

async function userForArgs(args: ParsedArgs): Promise<UserRecord> {
  if (args.uid != null) return auth.getUser(args.uid);
  if (args.email != null) return auth.getUserByEmail(args.email);
  throw new Error("Unreachable: uid or email required.");
}

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));
  const user = await userForArgs(args);
  const currentClaims = user.customClaims ?? {};
  await auth.setCustomUserClaims(user.uid, {
    ...currentClaims,
    admin: args.admin,
  });

  console.log(args.admin ? "Admin claim enabled." : "Admin claim disabled.");
  console.log(`projectId: ${projectId}`);
  console.log(`uid: ${user.uid}`);
  console.log(`email: ${user.email ?? "(none)"}`);
  console.log("The user must refresh their ID token or sign in again.");
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await deleteApp(app);
  });
