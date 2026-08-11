[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

$requiredFiles = @(
    "AGENTS.md",
    "SECURITY.md",
    "README.md",
    "Containerfile",
    "compose.yaml",
    ".github/dependabot.yml",
    "docs/PRODUCT_CHARTER.md",
    "docs/ARCHITECTURE.md",
    "docs/DATABASE_ARCHITECTURE.md",
    "docs/MODULAR_MONOLITH_CONTRACT.md",
    "docs/ENGINEERING_STANDARDS.md",
    "docs/MODULE_OWNERSHIP.md",
    "docs/ROADMAP.md",
    "docs/DEVELOPMENT_CONTINUITY.md",
    "docs/GATE_1_FRAMEWORK_SPIKE.md",
    "docs/STATUS.md",
    "docs/DECISION_LOG.md",
    "docs/adr/0001-elixir-phoenix-modular-monolith.md",
    "docs/adr/0002-selective-ash-adoption-spike.md",
    "docs/adr/0003-specialist-runtime-authority.md",
    "docs/adr/0004-blockchain-is-an-optional-evidence-anchor.md",
    "docs/adr/0005-modular-monolith-and-code-discipline.md",
    "docs/adr/0006-operational-kernel-and-local-ha-qualification.md",
    "docs/adr/0007-postgresql-19-data-platform-foundation.md",
    "config/module_catalog.json",
    "config/database_policy.json",
    "config/toolchain.json",
    "config/code_policy.json",
    "config/code_size_exceptions.json",
    "scripts/setup_elixir_toolchain.ps1",
    "scripts/setup_framework_tools.ps1",
    "scripts/start_local_postgres.ps1",
    "scripts/deploy_local_qualification.ps1",
    "scripts/support/write_local_credential.ps1",
    "scripts/verify_code_discipline.ps1",
    "scripts/verify_architecture_boundaries.ps1",
    "scripts/verify_database_policy.ps1",
    "scripts/security/ArtifactIntegrity.psm1",
    "scripts/verify_production_security.exs",
    "deploy/postgres/bootstrap.sql",
    "deploy/postgres/verify_core_baseline.sql",
    "deploy/postgres/verify_local_platform.sql",
    "test/security/artifact_integrity_test.ps1",
    "test/security/local_credential_acl_test.ps1"
)

$missing = @(
    $requiredFiles | Where-Object {
        -not (Test-Path -LiteralPath (Join-Path $repoRoot $_) -PathType Leaf)
    }
)

if ($missing.Count -gt 0) {
    throw "Missing required foundation files: $($missing -join ', ')"
}

$catalogPath = Join-Path $repoRoot "config/module_catalog.json"
$catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
$toolchainPath = Join-Path $repoRoot "config/toolchain.json"
$toolchain = Get-Content -LiteralPath $toolchainPath -Raw | ConvertFrom-Json

if ($catalog.schema_version -ne 1) {
    throw "Unsupported module catalog schema version: $($catalog.schema_version)"
}

if ($toolchain.schema_version -ne 1) {
    throw "Unsupported toolchain schema version: $($toolchain.schema_version)"
}

foreach ($requiredVersion in @("elixir", "erlang_otp", "phoenix_new", "hex", "rebar3")) {
    if ([string]::IsNullOrWhiteSpace($toolchain.primary.$requiredVersion)) {
        throw "Primary toolchain version '$requiredVersion' must be pinned"
    }
}

foreach ($artifactName in @("otp_archive", "elixir_archive")) {
    $artifactUrl = $toolchain.bootstrap."${artifactName}_url"
    $artifactSha256 = $toolchain.bootstrap."${artifactName}_sha256"
    if ($artifactUrl -notmatch '^https://') {
        throw "$artifactName URL must use HTTPS"
    }
    if ($artifactSha256 -cnotmatch '^[0-9A-F]{64}$') {
        throw "$artifactName SHA-256 must contain 64 uppercase hexadecimal characters"
    }
    if ([long]$toolchain.bootstrap."${artifactName}_size_bytes" -le 0) {
        throw "$artifactName size pin must be positive"
    }
}

$toolchainSetupText = Get-Content -LiteralPath (Join-Path $repoRoot "scripts/setup_elixir_toolchain.ps1") -Raw
if ($toolchainSetupText -notmatch 'Assert-FileSha256' -or
    $toolchainSetupText -notmatch 'Expand-SafeZipArchive' -or
    $toolchainSetupText -notmatch 'Assert-VerifiedInstallDirectory' -or
    $toolchainSetupText -notmatch 'New-VerifiedInstallReceipt' -or
    $toolchainSetupText -notmatch '--max-filesize' -or
    $toolchainSetupText -notmatch '--remove-on-error' -or
    $toolchainSetupText -match '\.Substring\(' -or
    $toolchainSetupText -match 'install\.bat') {
    throw "Language setup must bound, verify, safely install, and revalidate exact OTP and Elixir archives"
}

foreach ($artifactName in @("hex_archive", "rebar3", "phx_new_package")) {
    $artifactUrl = $toolchain.bootstrap."${artifactName}_url"
    $artifactSha512 = $toolchain.bootstrap."${artifactName}_sha512"
    if ($artifactUrl -notmatch '^https://') {
        throw "$artifactName URL must use HTTPS"
    }
    if ($artifactSha512 -notmatch '^[0-9A-Fa-f]{128}$') {
        throw "$artifactName SHA-512 must contain 128 hexadecimal characters"
    }
    if ([long]$toolchain.bootstrap."${artifactName}_size_bytes" -le 0) {
        throw "$artifactName size pin must be positive"
    }
}

if ($toolchain.bootstrap.phx_new_contents_sha512 -cnotmatch '^[0-9A-F]{128}$') {
    throw "Phoenix inner contents SHA-512 must contain 128 uppercase hexadecimal characters"
}

$frameworkSetupText = Get-Content -LiteralPath (Join-Path $repoRoot "scripts/setup_framework_tools.ps1") -Raw
if ($frameworkSetupText -notmatch 'Assert-FileSha512' -or
    $frameworkSetupText -notmatch 'Expand-SafeTarArchive' -or
    $frameworkSetupText -notmatch 'Assert-VerifiedInstallDirectory' -or
    $frameworkSetupText -notmatch '--max-filesize' -or
    $frameworkSetupText -notmatch '--remove-on-error' -or
    $frameworkSetupText -match '\.Substring\(' -or
    $frameworkSetupText -match 'tar\.exe' -or
    $frameworkSetupText -match 'local\.rebar\s+--if-missing' -or
    $frameworkSetupText -match 'archive\.install\s+hex\s+phx_new' -or
    $frameworkSetupText -notmatch 'archive\.build') {
    throw "Framework setup must verify pinned Hex, Rebar3, and Phoenix artifacts before installation"
}

$allowedStatuses = @("planned", "in_progress", "existing", "optional", "deferred")
$allOwners = @($catalog.modules) + @($catalog.external_systems)
$ownerIds = @($allOwners | ForEach-Object { $_.id })
$duplicateOwners = @(
    $ownerIds |
        Group-Object |
        Where-Object Count -gt 1 |
        ForEach-Object Name
)

if ($duplicateOwners.Count -gt 0) {
    throw "Duplicate module or external-system identifiers: $($duplicateOwners -join ', ')"
}

$recordOwners = @{}
foreach ($owner in $allOwners) {
    if ([string]::IsNullOrWhiteSpace($owner.id)) {
        throw "Every module and external system requires a non-empty id"
    }
    if ($allowedStatuses -notcontains $owner.status) {
        throw "Owner '$($owner.id)' has unsupported status '$($owner.status)'"
    }
    if (@($owner.record_types).Count -eq 0) {
        throw "Owner '$($owner.id)' must declare at least one record type"
    }
    foreach ($recordType in @($owner.record_types)) {
        if ([string]::IsNullOrWhiteSpace($recordType)) {
            throw "Owner '$($owner.id)' declares an empty record type"
        }
        if ($recordOwners.ContainsKey($recordType)) {
            throw "Record type '$recordType' has multiple owners: '$($recordOwners[$recordType])' and '$($owner.id)'"
        }
        $recordOwners[$recordType] = $owner.id
    }
}

$statusText = Get-Content -LiteralPath (Join-Path $repoRoot "docs/STATUS.md") -Raw
if ($statusText -notmatch "## One active focus") {
    throw "docs/STATUS.md must contain the single-focus heading"
}

$architectureText = Get-Content -LiteralPath (Join-Path $repoRoot "docs/ARCHITECTURE.md") -Raw
if ($architectureText -notmatch "modular monolith") {
    throw "docs/ARCHITECTURE.md must declare the modular-monolith foundation"
}

Write-Output "Foundation verification passed."
Write-Output "Validated $($catalog.modules.Count) modules, $($catalog.external_systems.Count) external systems, and $($recordOwners.Count) uniquely owned record types."
Write-Output "Pinned Elixir $($toolchain.primary.elixir), Erlang/OTP $($toolchain.primary.erlang_otp), and Phoenix generator $($toolchain.primary.phoenix_new)."
