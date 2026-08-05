# Invalid DSC config fixtures

Intentionally broken JSON for `Test-ArcGISConfigurationJson.ps1` (module-rule negatives). Not for `Invoke-ArcGISConfiguration`.

Fixtures live at repo-root `testdata/` for local negative checks.

| File | Expected module-rule findings |
|------|-------------------------------|
| `invalid-deprecated-desktop.json` | `AllNodes` role `Desktop`; `ConfigData.DesktopVersion` |
| `invalid-geoevent-federation.json` | GeoEvent + `Federation` block |
| `invalid-additional-geoevent.json` | `GeoEvent` in `AdditionalServerRoles` |
| `invalid-allnodes.json` | Duplicate `NodeName`; empty `Role` |
