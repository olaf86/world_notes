# Note Roles and Permissions

World Notes has four practical roles around a note.

`maintainerIds` is a denormalized Firestore array containing the creator plus
delegated maintainers. The creator is still identified by `createdByUserId`;
that field decides creator-only actions.

| Role | Meaning |
| --- | --- |
| Creator | The original note creator and final authority. Stored in `createdByUserId`. |
| Maintainer | A delegated operator listed in `maintainerIds` but not `createdByUserId`. |
| Member | A private-note participant with an invite or valid unlock membership. |
| Visitor | A signed-in user discovering a public note by proximity. |

| Action | Creator | Maintainer | Member | Visitor |
| --- | --- | --- | --- | --- |
| See the note in My Notes | Yes | Yes | No | No |
| Receive My Notes message notifications | Yes | Yes | No | No |
| Read note content | Yes | Yes | Yes | Public/proximity only |
| Post messages | Yes | Yes | Yes | Public/proximity only |
| Close or re-open a thread | Yes | Yes | No | No |
| View an existing invite link | Yes | Yes | No | No |
| Create an invite link | Yes | Yes | No | No |
| Revoke an invite link | Yes | No | No | No |
| Remove a regular member's access | Yes | Yes | No | No |
| Promote or demote maintainers | Yes | No | No | No |
| Set or change the note lock | Yes | No | No | No |
| Archive a note | Yes | No | No | No |

Operational notes:

- `maintainerIds` intentionally includes `createdByUserId` so My Notes queries
  and maintainer notifications can use one array-contains query.
- Client and Cloud Functions may read legacy `ownerIds` during migration, but
  new writes should use `maintainerIds`.
- Invite-link revocation is creator-only because it invalidates an existing
  sharing channel for everyone.
