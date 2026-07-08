const admin = require("firebase-admin");

const projectId = process.env.GCLOUD_PROJECT || "world-notes-prod";
process.env.FIREBASE_AUTH_EMULATOR_HOST =
  process.env.FIREBASE_AUTH_EMULATOR_HOST || "127.0.0.1:9099";
process.env.FIRESTORE_EMULATOR_HOST =
  process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";

admin.initializeApp({projectId});

const db = admin.firestore();
const auth = admin.auth();

const screenshotUser = {
  email: "screenshot@example.com",
  password: "Passw0rd!",
  displayName: "World Notes Guide",
};

const otherUsers = [
  {uid: "screenshot_friend_mina", displayName: "Mina"},
  {uid: "screenshot_friend_ren", displayName: "Ren"},
  {uid: "screenshot_friend_sora", displayName: "Sora"},
];

const BASE32 = "0123456789bcdefghjkmnpqrstuvwxyz";

function encodeGeohash(lat, lng, precision = 6) {
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
      hash += BASE32[hashValue];
      bits = 0;
      hashValue = 0;
    }
  }
  return hash;
}

async function ensureAuthUser() {
  let userRecord;
  try {
    userRecord = await auth.getUserByEmail(screenshotUser.email);
    await auth.updateUser(userRecord.uid, {
      password: screenshotUser.password,
      displayName: screenshotUser.displayName,
      emailVerified: true,
    });
  } catch (error) {
    if (error.code !== "auth/user-not-found") {
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

async function deleteCollectionDocs(collectionRef) {
  const snapshot = await collectionRef.get();
  if (snapshot.empty) return;
  const batch = db.batch();
  snapshot.docs.forEach((doc) => batch.delete(doc.ref));
  await batch.commit();
}

async function resetSeedData(user) {
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
    db.collection("users").doc(user.uid).collection("nearbyNotificationPlaces"),
  );
  await deleteCollectionDocs(
    db.collection("users").doc(user.uid).collection("notificationSettings"),
  );
}

function timestamp(date) {
  return admin.firestore.Timestamp.fromDate(date);
}

function daysFrom(now, days) {
  return new Date(now.getTime() + days * 24 * 60 * 60 * 1000);
}

function hoursBefore(now, hours) {
  return new Date(now.getTime() - hours * 60 * 60 * 1000);
}

function placeData(user, now, place) {
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
    icon: place.icon,
    createdByUserId: user.uid,
    creatorName: user.displayName,
    maintainerIds: [user.uid],
    createdAt: timestamp(hoursBefore(now, place.createdHoursAgo)),
    publishAt: timestamp(hoursBefore(now, place.publishHoursAgo ?? 1)),
    messageCount: place.messages.length,
    lastMessageAt: timestamp(hoursBefore(now, place.lastMessageHoursAgo)),
    visibility: place.visibility || "public",
    passwordVersion: place.visibility === "private" ? 1 : 0,
    lockType: place.visibility === "private" ? "password" : null,
    lockHint: place.visibility === "private" ? "The place where we met" : null,
    isOpen: place.isOpen !== false,
    isArchived: place.isArchived === true,
    archivedAt: place.isArchived ? timestamp(hoursBefore(now, 8)) : null,
    expiresAt: timestamp(daysFrom(now, place.expiresInDays)),
    footprintEnabled: true,
    visitorCount: place.visitors.length,
  };
}

async function seedUsers(user) {
  await db.collection("users").doc(user.uid).set({
    displayName: user.displayName,
    email: user.email,
    photoUrl: null,
    isPremium: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  for (const other of otherUsers) {
    await db.collection("users").doc(other.uid).set({
      displayName: other.displayName,
      email: null,
      photoUrl: null,
      isPremium: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
}

async function seedPlace(user, now, place) {
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

async function seedNearbyAlert(user, now, place) {
  await db
    .collection("users")
    .doc(user.uid)
    .collection("nearbyNotificationPlaces")
    .doc(place.id)
    .set({
      placeId: place.id,
      title: place.title,
      colorHex: place.colorHex,
      icon: place.icon,
      latitude: place.latitude,
      longitude: place.longitude,
      radiusMeters: 1000,
      expiresAt: timestamp(daysFrom(now, place.expiresInDays)),
      enabled: true,
      state: "active",
      lastReadMessageAt: timestamp(hoursBefore(now, 10)),
      lastNotifiedMessageAt: timestamp(hoursBefore(now, 3)),
      inRange: true,
      inRangeUntil: timestamp(hoursBefore(now, -1)),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
}

async function main() {
  const user = await ensureAuthUser();
  const now = new Date();

  const places = [
    {
      id: "wn_tokyo_station",
      title: "Tokyo Station Time Capsule",
      subtitle: "Travel tips left by people passing through Marunouchi.",
      latitude: 35.681236,
      longitude: 139.767125,
      colorHex: "#2563EB",
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
          content: "The north dome is quiet in the morning. Good place to plan the day.",
          hoursAgo: 4,
        },
        {
          id: "msg_tokyo_02",
          content: "Left a tiny route idea: walk toward the palace after coffee.",
          hoursAgo: 2,
        },
        {
          id: "msg_tokyo_03",
          userName: "Ren",
          userId: "screenshot_friend_ren",
          content: "Found this note while changing trains. Nice little city breadcrumb.",
          hoursAgo: 1,
        },
      ],
    },
    {
      id: "wn_marunouchi_cafe",
      title: "Marunouchi Morning Coffee",
      subtitle: "A private planning note for a quiet meetup.",
      latitude: 35.68205,
      longitude: 139.76485,
      colorHex: "#D97706",
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
          content: "Meet by the window seats. The second floor is usually calm.",
          hoursAgo: 7,
        },
        {
          id: "msg_cafe_02",
          content: "Added this as a private note so only the invited group sees it.",
          hoursAgo: 6,
        },
      ],
    },
    {
      id: "wn_imperial_garden",
      title: "Garden Walk Ideas",
      subtitle: "A public note for slow walks and photo stops.",
      latitude: 35.68518,
      longitude: 139.75808,
      colorHex: "#16A34A",
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
          content: "The path along the moat is best just before sunset.",
          hoursAgo: 12,
        },
      ],
    },
    {
      id: "wn_archived_memory",
      title: "Archived Launch Memory",
      subtitle: "An old note kept for My Notes archive screenshots.",
      latitude: 35.6802,
      longitude: 139.7691,
      colorHex: "#64748B",
      icon: "star",
      isArchived: true,
      createdHoursAgo: 240,
      lastMessageHoursAgo: 180,
      expiresInDays: 20,
      visitors: [],
      messages: [
        {
          id: "msg_archived_01",
          content: "This archived note shows how old places remain readable.",
          hoursAgo: 180,
        },
      ],
    },
  ];

  await resetSeedData(user);
  await seedUsers(user);
  for (const place of places) {
    await seedPlace(user, now, place);
  }
  await seedNearbyAlert(user, now, places[0]);

  console.log("Seed completed for World Notes screenshot mode.");
  console.log(`projectId: ${projectId}`);
  console.log(`uid: ${user.uid}`);
  console.log(`email: ${user.email}`);
  console.log("places:", places.map((place) => place.id).join(", "));
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await admin.app().delete();
  });
