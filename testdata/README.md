# Invalid DSC config fixtures

Intentionally broken JSON for local negative checks of `Test-ArcGISConfigurationJson.ps1`. Not for `Invoke-ArcGISConfiguration`.

Point the validator at this folder; module rules report the issues (folder run expects exit code 1 because of invalid fixtures):

```powershell
.\ConfigurationSchemas\Test-ArcGISConfigurationJson.ps1 -Path .\testdata
```

Directories expand recursively (`testdata\**\*.json`).

## Minimal fixtures

| File | Typical findings |
|------|------------------|
| `invalid-deprecated-desktop.json` | `AllNodes` role `Desktop`; `ConfigData.DesktopVersion` |
| `invalid-deprecated-insights.json` | `ConfigData.InsightsVersion`; `ConfigData.OldInsightsVersion` |
| `invalid-webadaptor-adminaccess.json` | `ConfigData.WebAdaptor.AdminAccessEnabled` ignored note |
| `invalid-geoevent-federation.json` | GeoEvent + `Federation` block |
| `invalid-additional-geoevent.json` | `GeoEvent` in `AdditionalServerRoles` |
| `invalid-allnodes.json` | Duplicate `NodeName`; empty `Role` |
| `invalid-allnodes-blank-role.json` | Blank `Role`; unnamed node with empty `Role` |
| `invalid-malformed.json` | Invalid JSON (trailing comma) |
| `valid-minimal.json` | Passes module rules (positive control) |

## SampleConfig-based fixtures

Derived from `SampleConfigs/v5/v5.1.1/` with invalid data injected (placeholder style preserved).

| File | Based on | Typical findings |
|------|----------|------------------|
| `sampleconfigs/BaseDeployment-SingleMachine-invalid-desktop.json` | `Base Deployment/BaseDeployment-SingleMachine.json` | Desktop role; `DesktopVersion`; `WebAdaptor.AdminAccessEnabled` |
| `sampleconfigs/BaseDeployment-DualMachine-invalid-allnodes.json` | `Base Deployment/BaseDeployment-DualMachine.json` | Duplicate `NodeName`; empty `Role`; `WebAdaptor.AdminAccessEnabled` |
| `sampleconfigs/GISServer-GeoEvent-invalid-federation.json` | `Gis Servers/GISServer-GeoEvent.json` | GeoEvent + `Federation` (same shape as upstream sample) |
| `sampleconfigs/GISServer-GeneralPurpose-MultiServerRoles-invalid-geoevent.json` | `Gis Servers/GISServer-GeneralPurpose-MultiServerRoles.json` | `Geoevent` in `AdditionalServerRoles` (same shape as upstream sample) |
| `sampleconfigs/GISServer-GeneralPurpose-invalid-insights.json` | `Gis Servers/GISServer-GeneralPurpose.json` | `InsightsVersion`; `OldInsightsVersion` |
