#Requires -Version 5.1
<#
.SYNOPSIS
    Validate ArcGIS PowerShell DSC configuration JSON files.

.DESCRIPTION
    Runs module semantic rules (deprecated keys, GeoEvent split-file rules, AllNodes
    integrity). Optionally validates against ConfigurationSchemas/vX.Y.Z.json using
    Test-Json -SchemaFile (PowerShell 7.4+ required for draft 2020-12).

    Intended as a standalone contribution under ConfigurationSchemas/ in
    Esri/arcgis-powershell-dsc. Does not import the ArcGIS DSC module.

.PARAMETER Path
    One or more configuration JSON file paths.

.PARAMETER Version
    Module version used in deprecation messages. Default 5.1.1.

.PARAMETER Schema
    Also validate each file against the JSON Schema with Test-Json -SchemaFile.

.PARAMETER SchemaPath
    Path to the schema JSON. Default: sibling v5.1.1.json next to this script
    (when installed under ConfigurationSchemas/).

.PARAMETER Strict
    Throw on the first file that fails validation.

.EXAMPLE
    .\Test-ArcGISConfigurationJson.ps1 -Path .\SampleConfigs\v5\v5.1.1\Base Deployment\BaseDeployment-SingleMachine.json

.EXAMPLE
    .\Test-ArcGISConfigurationJson.ps1 -Path .\my-config.json -Schema
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
    [Alias('FullName')]
    [string[]]$Path,

    [string]$Version = '5.1.1',

    [switch]$Schema,

    [string]$SchemaPath,

    [switch]$Strict
)

$ErrorActionPreference = 'Stop'

$script:ValidatorRoot = $PSScriptRoot

# Embedded rules (module 5.1.0+). Kept in-script so Esri ConfigurationSchemas/
# stays flat (schemas + this script only — no rules/ subdirectory).
function Get-ArcGISConfigurationDeprecatedRules {
    $json = @'
{
  "moduleVersion": "5.1.0",
  "deprecatedAllNodesRoles": ["Desktop"],
  "deprecatedConfigDataKeys": [
    "DesktopVersion",
    "InsightsVersion",
    "OldInsightsVersion"
  ],
  "notes": {
    "WebAdaptor.AdminAccessEnabled": "ConfigData.WebAdaptor.AdminAccessEnabled is ignored from ArcGIS Enterprise 11.5; the module forces true."
  }
}
'@
    return $json | ConvertFrom-Json
}

function Test-ArcGISConfigurationDeprecatedKeys {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config,

        [string]$ModuleVersion = '5.1.1'
    )

    $issues = [System.Collections.Generic.List[string]]::new()
    if ($ModuleVersion -lt '5.1.0') { return @() }

    $rules = Get-ArcGISConfigurationDeprecatedRules

    foreach ($node in @($Config.AllNodes)) {
        foreach ($badRole in @($rules.deprecatedAllNodesRoles)) {
            if ($node.Role -contains $badRole) {
                $issues.Add("AllNodes role '$badRole' is deprecated in module $ModuleVersion (node $($node.NodeName)).")
            }
        }
    }

    if ($Config.ConfigData) {
        foreach ($key in @($rules.deprecatedConfigDataKeys)) {
            if ($Config.ConfigData.PSObject.Properties.Name -contains $key) {
                $issues.Add("ConfigData.$key is deprecated in module $ModuleVersion.")
            }
        }

        if ($Config.ConfigData.WebAdaptor -and
            ($Config.ConfigData.WebAdaptor.PSObject.Properties.Name -contains 'AdminAccessEnabled')) {
            $note = $rules.notes.'WebAdaptor.AdminAccessEnabled'
            if ($note) { $issues.Add([string]$note) }
            else { $issues.Add('ConfigData.WebAdaptor.AdminAccessEnabled is deprecated.') }
        }
    }

    return @($issues)
}

function Test-ArcGISConfigurationSplitRules {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config
    )

    $issues = [System.Collections.Generic.List[string]]::new()
    if (-not $Config.ConfigData) { return @() }

    $role = $Config.ConfigData.ServerRole

    if ($role -eq 'GeoEvent' -and $Config.ConfigData.Federation) {
        $issues.Add('GeoEvent deployment must not include a Federation block.')
    }

    if ($role -eq 'GeneralPurposeServer' -and
        $Config.ConfigData.AdditionalServerRoles -icontains 'GeoEvent') {
        $issues.Add('GeoEvent must not be listed in AdditionalServerRoles; use a separate JSON with ServerRole GeoEvent.')
    }

    return @($issues)
}

function Test-ArcGISConfigurationAllNodes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config
    )

    $issues = [System.Collections.Generic.List[string]]::new()
    $seen = @{}
    foreach ($node in @($Config.AllNodes)) {
        $name = [string]$node.NodeName
        if ($seen.ContainsKey($name)) {
            $issues.Add("Duplicate NodeName '$name' in AllNodes.")
        }
        else {
            $seen[$name] = $true
        }

        $roles = @($node.Role)
        if ($roles.Count -eq 0 -or ($roles.Count -eq 1 -and [string]::IsNullOrWhiteSpace([string]$roles[0]))) {
            $display = if ([string]::IsNullOrWhiteSpace($name)) { '(unnamed)' } else { $name }
            $issues.Add("Node '$display' has no Role assigned.")
        }
    }

    return @($issues)
}

function Get-ArcGISConfigurationDscRoots {
    # ConfigurationSchemas/<this script> → repo root is parent
    $root = Join-Path $script:ValidatorRoot '..'
    if (Test-Path -LiteralPath (Join-Path $root 'SampleConfigs')) {
        try { (Resolve-Path -LiteralPath $root).Path } catch { $null }
    }
}

function Resolve-ArcGISConfigurationInputPath {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )

    if (Test-Path -LiteralPath $FilePath) {
        return (Resolve-Path -LiteralPath $FilePath).Path
    }

    $rel = $FilePath -replace '^\.[\\/]', ''
    # Resolve relative paths against the DSC repo root (SampleConfigs/, testdata/, ...)
    foreach ($root in @(Get-ArcGISConfigurationDscRoots)) {
        if ([string]::IsNullOrWhiteSpace($root)) { continue }
        $candidate = Join-Path $root $rel
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    $hint = "File not found: $FilePath"
    if ($FilePath -match '\\Base$' -or $FilePath -notmatch '\.json$') {
        $hint += " Tip: quote -Path when folders contain spaces (e.g. -Path '.\SampleConfigs\v5\v5.1.1\Base Deployment\BaseDeployment-SingleMachine.json')."
    }
    else {
        $hint += " Tip: use a path relative to the DSC repo root (SampleConfigs\\..., testdata\\...)."
    }
    throw $hint
}

function Resolve-ArcGISConfigurationSchemaPath {
    param([string]$ExplicitPath)

    if ($ExplicitPath) {
        return (Resolve-ArcGISConfigurationInputPath -FilePath $ExplicitPath)
    }

    $sibling = Join-Path $script:ValidatorRoot 'v5.1.1.json'
    if (Test-Path -LiteralPath $sibling) {
        return (Resolve-Path -LiteralPath $sibling).Path
    }

    foreach ($root in @(Get-ArcGISConfigurationDscRoots)) {
        $repoSchema = Join-Path $root 'ConfigurationSchemas\v5.1.1.json'
        if (Test-Path -LiteralPath $repoSchema) {
            return (Resolve-Path -LiteralPath $repoSchema).Path
        }
    }

    throw "Schema file not found. Pass -SchemaPath or place v5.1.1.json next to this script."
}

function Test-ArcGISConfigurationSupportsSchemaValidation {
    $psMajor = $PSVersionTable.PSVersion.Major
    $psMinor = $PSVersionTable.PSVersion.Minor
    if ($psMajor -gt 7) { return $true }
    if ($psMajor -eq 7 -and $psMinor -ge 4) { return $true }
    return $false
}

function Test-ArcGISConfigurationSchema {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConfigPath,

        [Parameter(Mandatory)]
        [string]$SchemaFile
    )

    $issues = [System.Collections.Generic.List[string]]::new()

    if (-not (Test-ArcGISConfigurationSupportsSchemaValidation)) {
        $issues.Add("JSON Schema validation (-Schema) requires PowerShell 7.4+ (current: $($PSVersionTable.PSVersion)). Module rules still apply without -Schema.")
        return @($issues)
    }

    try {
        $ok = Test-Json -Path $ConfigPath -SchemaFile $SchemaFile -ErrorAction Stop
        if (-not $ok) {
            $issues.Add("JSON Schema validation failed against '$SchemaFile'.")
        }
    }
    catch {
        $msg = $_.Exception.Message
        if ([string]::IsNullOrWhiteSpace($msg)) { $msg = "$_" }
        $issues.Add("JSON Schema validation failed against '$SchemaFile': $msg")
    }

    return @($issues)
}

function Test-ArcGISConfigurationJsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [string]$ModuleVersion = '5.1.1',
        [switch]$Schema,
        [string]$SchemaFile,
        [switch]$Strict
    )

    $resolvedPath = Resolve-ArcGISConfigurationInputPath -FilePath $FilePath
    $raw = Get-Content -LiteralPath $resolvedPath -Raw -Encoding UTF8
    $config = $null
    try {
        $config = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        if ($Strict) { throw "Invalid JSON in ${resolvedPath}: $_" }
        return [pscustomobject]@{
            Path       = $resolvedPath
            ValidJson  = $false
            IssueCount = 1
            Issues     = @("Invalid JSON: $_")
            Passed     = $false
        }
    }

    $allIssues = [System.Collections.Generic.List[string]]::new()
    foreach ($issue in @(Test-ArcGISConfigurationDeprecatedKeys -Config $config -ModuleVersion $ModuleVersion)) {
        $allIssues.Add($issue)
    }
    foreach ($issue in @(Test-ArcGISConfigurationSplitRules -Config $config)) {
        $allIssues.Add($issue)
    }
    foreach ($issue in @(Test-ArcGISConfigurationAllNodes -Config $config)) {
        $allIssues.Add($issue)
    }

    if ($Schema) {
        foreach ($issue in @(Test-ArcGISConfigurationSchema -ConfigPath $resolvedPath -SchemaFile $SchemaFile)) {
            $allIssues.Add($issue)
        }
    }

    $result = [pscustomobject]@{
        Path       = $resolvedPath
        ValidJson  = $true
        IssueCount = $allIssues.Count
        Issues     = @($allIssues)
        Passed     = ($allIssues.Count -eq 0)
    }

    if ($Strict -and -not $result.Passed) {
        throw "Validation failed for ${resolvedPath}: $($allIssues -join '; ')"
    }

    return $result
}

# --- entrypoint ---
$resolvedSchema = $null
if ($Schema) {
    $resolvedSchema = Resolve-ArcGISConfigurationSchemaPath -ExplicitPath $SchemaPath
}

$results = [System.Collections.Generic.List[object]]::new()
foreach ($file in $Path) {
    $results.Add((Test-ArcGISConfigurationJsonFile `
            -FilePath $file `
            -ModuleVersion $Version `
            -Schema:$Schema `
            -SchemaFile $resolvedSchema `
            -Strict:$Strict))
}

$results | Format-Table Path, Passed, IssueCount -AutoSize
foreach ($r in $results) {
    if ($r.Issues.Count -gt 0) {
        Write-Host ""
        Write-Host $r.Path -ForegroundColor Cyan
        foreach ($issue in $r.Issues) {
            Write-Warning "  $issue"
        }
    }
}

if ($results | Where-Object { -not $_.Passed }) {
    exit 1
}
exit 0
