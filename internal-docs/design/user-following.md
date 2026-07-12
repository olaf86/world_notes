# User Following

## Goal

Add one-way user following plus screens for a user's followers and following
lists. The first version should stay small, keep Firestore as the source of
truth, and avoid data shapes that make a later move to SQL Connect or Neo4j
awkward.

## Storage Strategy

Start with a flat edge collection:

```text
publicProfiles/{uid}
  displayName: string
  photoUrl: string?
  followerCount: number
  followingCount: number
  createdAt: timestamp
  updatedAt: timestamp

socialEdges/{edgeId}
  followerUid: string
  followeeUid: string
  createdAt: timestamp
```

`socialEdges` is the source of truth for relationships. The document id is a
stable encoding of `(followerUid, followeeUid)`, but migrations should rely on
the stored fields rather than parsing ids.

`publicProfiles` contains only public display data and social counters. The
private `users/{uid}` document remains owner-only because it includes email and
other account fields.

## Query Shape

Follow lists must use cursor pagination.

```text
following:
  socialEdges
    where followerUid == uid
    orderBy createdAt desc
    limit 20

followers:
  socialEdges
    where followeeUid == uid
    orderBy createdAt desc
    limit 20
```

Do not use `offset`, and do not load all edges at once. Each page reads up to
20 edge documents, then reads the matching `publicProfiles` documents in
parallel. This is a client-side join, but the page size keeps the cost bounded.

## Update Flow

Clients call `setUserFollow({targetUserId, following})`.

The callable function:

- requires authentication and App Check
- rejects self-follow
- verifies that the target user exists
- creates missing public profile mirrors for the caller and target
- creates or deletes one `socialEdges` document in a transaction
- updates `publicProfiles.followingCount` and `followerCount` in the same
  transaction
- treats repeated requests for the same final state as no-ops

Direct client writes to `socialEdges` are denied. Clients may create/update
only their own public display fields in `publicProfiles`; social counters are
server-managed.

All public-profile fields are required except that `photoUrl` may be `null`.

## Migration Path

The flat edge document maps directly to SQL and graph relationships.

```sql
follows(
  follower_uid text not null,
  followee_uid text not null,
  created_at timestamptz not null,
  primary key (follower_uid, followee_uid)
)
```

```cypher
(:User {uid: followerUid})-[:FOLLOWS {createdAt: createdAt}]->
(:User {uid: followeeUid})
```

If social queries outgrow Firestore, move in phases:

1. Keep Firestore as source of truth and mirror `socialEdges` to SQL Connect.
2. Make SQL Connect the source of truth for social relationships once the app
   needs joins such as mutual follows or friend-of-friend queries.
3. Mirror SQL follows into Neo4j for recommendations, graph traversal, or
   community detection.

## Deferred Optimizations

- Edge display snapshots are intentionally omitted in v1. They would reduce
  list reads but make profile updates fan out across all edges.
- Sharded counters are not needed at launch. If a popular account receives many
  follows per second, replace direct `publicProfiles` counter updates with
  sharded counters or async aggregation.
- Recommendation feeds and multi-hop graph queries are out of the initial
  scope.
