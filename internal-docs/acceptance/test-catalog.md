# Acceptance Test Coverage Catalog

This table shows where each feature or risk is verified. Execution results are
tracked separately in JUnit reports. `Covered` means the primary behavior is
verified, `Partial` means only part of it is verified, and `Planned` identifies
future coverage.

| Feature or risk | Priority | Unit | Widget | Maestro | Manual | Test ID or notes |
|---|---:|---:|---:|---:|---:|---|
| Sign in with email and open the map | P0 | - | Partial | Covered | - | `AT-001`; Widget covers stable selectors only |
| Navigate between the map and nearby-notes list | P0 | Covered | Covered | Covered | - | `AT-001` |
| Open note details from the map | P0 | Covered | Covered | Planned | - | Next automation target |
| Create a note | P0 | Partial | Covered | Planned | - | Planned |
| Send a message to a note | P0 | Partial | Partial | Planned | - | Planned |
| Recover after denying location permission | P0 | Covered | Covered | Planned | Physical device | `MT-001`; verify OS differences |
| Enforce private and locked-note access | P1 | Covered | Covered | Planned | - | Planned |
| Hide blocked or reported content | P1 | Covered | Covered | Planned | - | Planned |
| Open a note from a push notification | P0 | Covered | Covered | Dedicated environment | Covered | `MT-002` |
| Purchase and restore PRO | P0 | Covered | Covered | Sandbox candidate | Covered | `MT-003` |
| Display ads and UMP consent correctly | P1 | Covered | Covered | Dedicated environment | Covered | `MT-004` |
| Validate map rendering and interaction quality | P2 | - | - | - | Covered | `MT-005` |

## Automated Flows

| ID | User journey | Tags | Platforms |
|---|---|---|---|
| `AT-001` | Sign in, then navigate to the map, nearby-notes list, and profile | `smoke`, `p0`, `auth`, `map` | iOS / Android |
