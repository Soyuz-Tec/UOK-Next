[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$policyPath = Join-Path $repoRoot "config\database_policy.json"
$policy = Get-Content -LiteralPath $policyPath -Raw | ConvertFrom-Json

if ($policy.schema_version -ne 1) {
    throw "Unsupported database policy schema version: $($policy.schema_version)"
}

$postgres = $policy.postgresql
if ($postgres.target_major -ne 19 -or
    $postgres.compatibility_release -ne "19beta2" -or
    $postgres.production_prerelease_allowed -ne $false) {
    throw "PostgreSQL 19 Beta 2 must be qualification-only and production must reject prereleases"
}

if ($postgres.compatibility_image -cnotmatch '^docker\.io/library/postgres@sha256:[0-9a-f]{64}$') {
    throw "The PostgreSQL compatibility image must use an immutable Docker Hub digest"
}

$cluster = $postgres.cluster
if ($cluster.encoding -ne "UTF8" -or
    $cluster.locale_provider -ne "builtin" -or
    $cluster.builtin_locale -ne "PG_UNICODE_FAST" -or
    $cluster.timezone -ne "UTC" -or
    $cluster.data_checksums -ne $true -or
    $cluster.password_encryption -ne "scram-sha-256") {
    throw "The PostgreSQL cluster identity has drifted from the accepted baseline"
}

$requiredExtensions = @($postgres.extensions.required)
$allowedExtensions = @($postgres.extensions.allowed)
foreach ($extension in $requiredExtensions) {
    if ($allowedExtensions -notcontains $extension) {
        throw "Required extension '$extension' is absent from the extension allowlist"
    }
}

$budget = $policy.connection_budget
$applicationConnections = $budget.application_replicas * $budget.application_pool_per_replica
$nonReservedConnections = $budget.local_max_connections -
    $budget.local_reserved_connections -
    $budget.local_superuser_reserved_connections

if ($applicationConnections -ge $nonReservedConnections -or
    $budget.application_role_limit -lt $applicationConnections -or
    $budget.application_role_limit -ge $nonReservedConnections) {
    throw "The local application connection budget has no safe operating headroom"
}

$roleIds = @($policy.roles | ForEach-Object { $_.id })
$duplicateRoleIds = @($roleIds | Group-Object | Where-Object Count -gt 1)
$requiredRoleIds = @(
    "uok_owner",
    "uok_migrator",
    "uok_app",
    "uok_outbox",
    "uok_monitor",
    "uok_backup",
    "uok_replication",
    "uok_break_glass"
)

if ($duplicateRoleIds.Count -gt 0 -or
    @($requiredRoleIds | Where-Object { $roleIds -notcontains $_ }).Count -gt 0) {
    throw "The production PostgreSQL role topology is incomplete or ambiguous"
}

$composeText = Get-Content -LiteralPath (Join-Path $repoRoot "compose.yaml") -Raw
$workflowText = Get-Content -LiteralPath (Join-Path $repoRoot ".github\workflows\foundation.yml") -Raw
$runtimeText = Get-Content -LiteralPath (Join-Path $repoRoot "config\runtime.exs") -Raw
$toolchain = Get-Content -LiteralPath (Join-Path $repoRoot "config\toolchain.json") -Raw |
    ConvertFrom-Json

if ($toolchain.infrastructure.postgres -ne $postgres.compatibility_release -or
    $toolchain.infrastructure.postgres_image -ne $postgres.compatibility_image) {
    throw "The toolchain and database policy disagree on the PostgreSQL qualification artifact"
}

foreach ($source in @($composeText, $workflowText)) {
    if (-not $source.Contains($postgres.compatibility_image)) {
        throw "A qualification environment does not use the policy-owned PostgreSQL image"
    }
}

if ($composeText -notmatch 'PG_UNICODE_FAST' -or
    $workflowText -notmatch 'PG_UNICODE_FAST' -or
    $runtimeText -notmatch 'DATABASE_CA_CERT_FILE' -or
    $runtimeText -notmatch 'target_server_type:\s*:primary' -or
    $runtimeText -notmatch '"POOL_SIZE",\s*"10",\s*1,\s*20') {
    throw "Database initialization, certificate trust, or primary-targeting controls are missing"
}

Write-Output "Database policy verification passed."
Write-Output "Qualified PostgreSQL $($postgres.compatibility_release); production target is major $($postgres.target_major) GA."
Write-Output "Application pools consume $applicationConnections of $nonReservedConnections non-reserved local slots."
