/* eslint-disable require-jsdoc, max-len, no-console */
import {deleteApp, initializeApp} from "firebase-admin/app";
import {getAuth, UserRecord} from "firebase-admin/auth";
import {
  CollectionReference,
  DocumentData,
  FieldValue,
  getFirestore,
  Timestamp,
} from "firebase-admin/firestore";

const projectId = process.env.GCLOUD_PROJECT || "world-notes-prod";
process.env.FIREBASE_AUTH_EMULATOR_HOST =
  process.env.FIREBASE_AUTH_EMULATOR_HOST || "127.0.0.1:9099";
process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";

const app = initializeApp({projectId});
const db = getFirestore(app);
const auth = getAuth(app);
const screenshotLocale = process.env.SCREENSHOT_LOCALE === "en" ? "en" : "ja";

function localized(english: string, japanese: string): string {
  return screenshotLocale === "ja" ? japanese : english;
}

interface ScreenshotUser {
  uid: string;
  email: string;
  password: string;
  displayName: string;
}

interface OtherUser {
  uid: string;
  displayName: string;
}

interface VisitorSeed {
  userId: string;
  displayName: string;
  firstVisitedHoursAgo: number;
  lastVisitedHoursAgo: number;
  visitCount: number;
}

interface MessageSeed {
  id: string;
  content: string;
  hoursAgo: number;
  userId?: string;
  userName?: string;
}

interface PlaceSeed {
  id: string;
  title: string;
  subtitle: string;
  latitude: number;
  longitude: number;
  colorHex: string;
  themeId:
    | "standard"
    | "aurora"
    | "citrus"
    | "botanical"
    | "neon"
    | "editorial";
  icon: string;
  createdHoursAgo: number;
  lastMessageHoursAgo: number;
  expiresInDays: number;
  visitors: VisitorSeed[];
  messages: MessageSeed[];
  visibility?: "public" | "private";
  publishHoursAgo?: number;
  isOpen?: boolean;
  isArchived?: boolean;
}

const screenshotUser = {
  email: "screenshot@example.com",
  password: "Passw0rd!",
  displayName: localized("World Notes Guide", "World Notes ガイド"),
};

const otherUsers: OtherUser[] = [
  {uid: "screenshot_friend_mina", displayName: "Mina"},
  {uid: "screenshot_friend_ren", displayName: "Ren"},
  {uid: "screenshot_friend_sora", displayName: "Sora"},
];

const base32 = "0123456789bcdefghjkmnpqrstuvwxyz";

function encodeGeohash(lat: number, lng: number, precision = 6): string {
  let minLat = -90.0;
  let maxLat = 90.0;
  let minLng = -180.0;
  let maxLng = 180.0;
  let hash = "";
  let bits = 0;
  let hashValue = 0;
  let isEven = true;

  while (hash.length < precision) {
    const mid = isEven ? (minLng + maxLng) / 2 : (minLat + maxLat) / 2;
    const value = isEven ? lng : lat;
    if (value >= mid) {
      hashValue = (hashValue << 1) + 1;
      if (isEven) {
        minLng = mid;
      } else {
        minLat = mid;
      }
    } else {
      hashValue = hashValue << 1;
      if (isEven) {
        maxLng = mid;
      } else {
        maxLat = mid;
      }
    }
    isEven = !isEven;
    bits++;
    if (bits === 5) {
      hash += base32[hashValue];
      bits = 0;
      hashValue = 0;
    }
  }
  return hash;
}

function isFirebaseError(error: unknown): error is {code: string} {
  return typeof error === "object" &&
    error != null &&
    "code" in error &&
    typeof (error as {code?: unknown}).code === "string";
}

async function ensureAuthUser(): Promise<ScreenshotUser> {
  let userRecord: UserRecord;
  try {
    userRecord = await auth.getUserByEmail(screenshotUser.email);
    await auth.updateUser(userRecord.uid, {
      password: screenshotUser.password,
      displayName: screenshotUser.displayName,
      emailVerified: true,
    });
  } catch (error) {
    if (!isFirebaseError(error) || error.code !== "auth/user-not-found") {
      throw error;
    }
    userRecord = await auth.createUser({
      email: screenshotUser.email,
      password: screenshotUser.password,
      displayName: screenshotUser.displayName,
      emailVerified: true,
    });
  }
  return {...screenshotUser, uid: userRecord.uid};
}

async function deleteCollectionDocs(
  collectionRef: CollectionReference<DocumentData>,
): Promise<void> {
  const snapshot = await collectionRef.get();
  if (snapshot.empty) return;
  const batch = db.batch();
  snapshot.docs.forEach((doc) => batch.delete(doc.ref));
  await batch.commit();
}

async function resetSeedData(user: ScreenshotUser): Promise<void> {
  const placeIds = [
    "wn_tokyo_station",
    "wn_marunouchi_cafe",
    "wn_imperial_garden",
    "wn_archived_memory",
  ];
  for (const placeId of placeIds) {
    const placeRef = db.collection("places").doc(placeId);
    await deleteCollectionDocs(placeRef.collection("messages"));
    await deleteCollectionDocs(placeRef.collection("visitors"));
    await deleteCollectionDocs(placeRef.collection("members"));
    await placeRef.delete();
  }

  await deleteCollectionDocs(
    db.collection("users").doc(user.uid).collection("notificationSettings"),
  );
}

function timestamp(date: Date): Timestamp {
  return Timestamp.fromDate(date);
}

function daysFrom(now: Date, days: number): Date {
  return new Date(now.getTime() + days * 24 * 60 * 60 * 1000);
}

function hoursBefore(now: Date, hours: number): Date {
  return new Date(now.getTime() - hours * 60 * 60 * 1000);
}

function placeData(
  user: ScreenshotUser,
  now: Date,
  place: PlaceSeed,
): DocumentData {
  const geohash = encodeGeohash(place.latitude, place.longitude, 6);
  return {
    latitude: place.latitude,
    longitude: place.longitude,
    geohash,
    mapGeohashMid: encodeGeohash(place.latitude, place.longitude, 5),
    discoveryGeohash: encodeGeohash(place.latitude, place.longitude, 3),
    title: place.title,
    subtitle: place.subtitle,
    colorHex: place.colorHex,
    themeId: place.themeId,
    icon: place.icon,
    createdByUserId: user.uid,
    creatorName: user.displayName,
    maintainerIds: [user.uid],
    createdAt: timestamp(hoursBefore(now, place.createdHoursAgo)),
    publishAt: timestamp(hoursBefore(now, place.publishHoursAgo ?? 1)),
    messageCount: place.messages.length,
    likeCount: 0,
    lastMessageAt: timestamp(hoursBefore(now, place.lastMessageHoursAgo)),
    visibility: place.visibility || "public",
    passwordVersion: place.visibility === "private" ? 1 : 0,
    lockType: place.visibility === "private" ? "password" : null,
    lockHint: place.visibility === "private" ?
      localized("The place where we met", "待ち合わせをした場所") : null,
    isOpen: place.isOpen !== false,
    isArchived: place.isArchived === true,
    archivedAt: place.isArchived ? timestamp(hoursBefore(now, 8)) : null,
    expiresAt: timestamp(daysFrom(now, place.expiresInDays)),
    footprintEnabled: true,
    visitorCount: place.visitors.length,
  };
}

async function seedUsers(user: ScreenshotUser): Promise<void> {
  await db.collection("users").doc(user.uid).set({
    displayName: user.displayName,
    email: user.email,
    photoUrl: null,
    isPremium: false,
    createdAt: FieldValue.serverTimestamp(),
  });

  for (const other of otherUsers) {
    await db.collection("users").doc(other.uid).set({
      displayName: other.displayName,
      email: null,
      photoUrl: null,
      isPremium: false,
      createdAt: FieldValue.serverTimestamp(),
    });
  }
}

async function seedPlace(
  user: ScreenshotUser,
  now: Date,
  place: PlaceSeed,
): Promise<void> {
  const placeRef = db.collection("places").doc(place.id);
  const data = placeData(user, now, place);
  await placeRef.set(data);

  if (place.visibility === "private") {
    await placeRef.collection("members").doc(user.uid).set({
      displayName: user.displayName,
      invited: true,
      isMaintainer: true,
      viaPasswordVersion: 1,
    });
  }

  for (const [index, message] of place.messages.entries()) {
    const messageTime = hoursBefore(now, message.hoursAgo);
    await placeRef.collection("messages").doc(message.id).set({
      placeId: place.id,
      userId: message.userId || user.uid,
      userName: message.userName || user.displayName,
      userPhotoUrl: null,
      content: message.content,
      imageStoragePaths: [],
      createdAt: timestamp(messageTime),
      publishAt: timestamp(messageTime),
      isScheduled: false,
      isDeleted: false,
      deletedAt: null,
      deletedReason: null,
      isVisible: true,
      isPubliclyVisible: true,
      isSensitive: false,
      reviewRequired: false,
      reportCount: 0,
      sortOrder: index,
    });
  }

  for (const visitor of place.visitors) {
    await placeRef.collection("visitors").doc(visitor.userId).set({
      userId: visitor.userId,
      displayName: visitor.displayName,
      photoUrl: null,
      firstVisitedAt: timestamp(hoursBefore(now, visitor.firstVisitedHoursAgo)),
      lastVisitedAt: timestamp(hoursBefore(now, visitor.lastVisitedHoursAgo)),
      visitCount: visitor.visitCount,
      isMaintainer: visitor.userId === user.uid,
    });
  }
}

function screenshotPlaces(user: ScreenshotUser): PlaceSeed[] {
  return [
    {
      id: "wn_tokyo_station",
      title: localized("Tokyo Station Time Capsule", "東京駅のタイムカプセル"),
      subtitle: localized(
        "Travel tips left by people passing through Marunouchi.",
        "丸の内を訪れた人が残す旅のヒント。",
      ),
      latitude: 35.681236,
      longitude: 139.767125,
      colorHex: "#2563EB",
      themeId: "standard",
      icon: "place",
      createdHoursAgo: 72,
      lastMessageHoursAgo: 2,
      expiresInDays: 90,
      visitors: [
        {
          userId: user.uid,
          displayName: user.displayName,
          firstVisitedHoursAgo: 72,
          lastVisitedHoursAgo: 2,
          visitCount: 4,
        },
        {
          userId: "screenshot_friend_mina",
          displayName: "Mina",
          firstVisitedHoursAgo: 40,
          lastVisitedHoursAgo: 4,
          visitCount: 2,
        },
        {
          userId: "screenshot_friend_ren",
          displayName: "Ren",
          firstVisitedHoursAgo: 18,
          lastVisitedHoursAgo: 8,
          visitCount: 1,
        },
      ],
      messages: [
        {
          id: "msg_tokyo_01",
          userName: "Mina",
          userId: "screenshot_friend_mina",
          content: localized(
            "The north dome is quiet in the morning. Good place to plan the day.",
            "朝の北口ドームは静かで、一日の予定を考えるのにぴったりです。",
          ),
          hoursAgo: 4,
        },
        {
          id: "msg_tokyo_02",
          content: localized(
            "Left a tiny route idea: walk toward the palace after coffee.",
            "コーヒーのあと皇居方面へ歩く、小さな散歩コースを残しました。",
          ),
          hoursAgo: 2,
        },
        {
          id: "msg_tokyo_03",
          userName: "Ren",
          userId: "screenshot_friend_ren",
          content: localized(
            "Found this note while changing trains. Nice little city breadcrumb.",
            "乗り換えの途中で見つけました。街に残された小さな道しるべですね。",
          ),
          hoursAgo: 1,
        },
      ],
    },
    {
      id: "wn_marunouchi_cafe",
      title: localized("Marunouchi Morning Coffee", "丸の内の朝カフェ"),
      subtitle: localized(
        "A private planning note for a quiet meetup.",
        "静かな待ち合わせのための非公開ノート。",
      ),
      latitude: 35.68205,
      longitude: 139.76485,
      colorHex: "#D97706",
      themeId: "citrus",
      icon: "restaurant",
      visibility: "private",
      createdHoursAgo: 48,
      lastMessageHoursAgo: 6,
      expiresInDays: 30,
      visitors: [
        {
          userId: user.uid,
          displayName: user.displayName,
          firstVisitedHoursAgo: 48,
          lastVisitedHoursAgo: 6,
          visitCount: 3,
        },
      ],
      messages: [
        {
          id: "msg_cafe_01",
          content: localized(
            "Meet by the window seats. The second floor is usually calm.",
            "窓際の席で待ち合わせ。2階はたいてい落ち着いています。",
          ),
          hoursAgo: 7,
        },
        {
          id: "msg_cafe_02",
          content: localized(
            "Added this as a private note so only the invited group sees it.",
            "招待したメンバーだけに見える非公開ノートにしました。",
          ),
          hoursAgo: 6,
        },
      ],
    },
    {
      id: "wn_imperial_garden",
      title: localized("Garden Walk Ideas", "皇居外苑のお散歩アイデア"),
      subtitle: localized(
        "A public note for slow walks and photo stops.",
        "ゆっくり歩きながら写真を楽しむための公開ノート。",
      ),
      latitude: 35.68518,
      longitude: 139.75808,
      colorHex: "#16A34A",
      themeId: "botanical",
      icon: "park",
      createdHoursAgo: 96,
      lastMessageHoursAgo: 12,
      expiresInDays: 180,
      visitors: [
        {
          userId: "screenshot_friend_sora",
          displayName: "Sora",
          firstVisitedHoursAgo: 96,
          lastVisitedHoursAgo: 12,
          visitCount: 2,
        },
      ],
      messages: [
        {
          id: "msg_garden_01",
          userName: "Sora",
          userId: "screenshot_friend_sora",
          content: localized(
            "The path along the moat is best just before sunset.",
            "お堀沿いの道は日没前の時間がいちばんきれいです。",
          ),
          hoursAgo: 12,
        },
      ],
    },
    {
      id: "wn_archived_memory",
      title: localized("Archived Launch Memory", "アーカイブした旅の思い出"),
      subtitle: localized(
        "An old note kept for My Notes archive screenshots.",
        "マイノートに残してある、以前の場所の記録。",
      ),
      latitude: 35.6802,
      longitude: 139.7691,
      colorHex: "#64748B",
      themeId: "editorial",
      icon: "star",
      isArchived: true,
      createdHoursAgo: 240,
      lastMessageHoursAgo: 180,
      expiresInDays: 20,
      visitors: [],
      messages: [
        {
          id: "msg_archived_01",
          content: localized(
            "This archived note shows how old places remain readable.",
            "アーカイブした場所の思い出も、あとから読み返せます。",
          ),
          hoursAgo: 180,
        },
      ],
    },
  ];
}

async function main(): Promise<void> {
  const user = await ensureAuthUser();
  const now = new Date();
  const places = screenshotPlaces(user);

  await resetSeedData(user);
  await seedUsers(user);
  for (const place of places) {
    await seedPlace(user, now, place);
  }

  console.log("Seed completed for World Notes screenshot mode.");
  console.log(`projectId: ${projectId}`);
  console.log(`uid: ${user.uid}`);
  console.log(`email: ${user.email}`);
  console.log(`locale: ${screenshotLocale}`);
  console.log("places:", places.map((place) => place.id).join(", "));
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await deleteApp(app);
  });
