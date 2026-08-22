# Pre-release Manual Checks

Keep only checks that depend on external services, physical devices, or human
judgment. Before adding a routine navigation or input check here, confirm that
it cannot reasonably be covered by Maestro or a Widget test.

| ID | Check | Target | When to run | Evidence |
|---|---|---|---|---|
| `MT-001` | Deny the initial location permission, then recover through the settings guidance | Physical iOS and Android devices | Release candidate | Record the result, device, and OS in the release notes |
| `MT-002` | Receive a real push notification and open its target note | Physical iOS and Android devices | Notification changes and release candidate | Screenshots of the notification and destination |
| `MT-003` | Purchase and restore PRO through Store Sandbox | Physical iOS and Android devices | Purchase changes and release candidate | Sandbox transaction result |
| `MT-004` | Confirm UMP consent and ad behavior for the applicable region and consent state | Physical iOS and Android devices | Ad changes | Screenshots for each tested state |
| `MT-005` | Confirm that map pan, zoom, pin selection, and rendering feel correct | Physical iOS and Android devices | Map UI changes | Record video only when an issue is found |
