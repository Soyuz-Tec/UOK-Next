[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "support\write_local_credential.ps1")

$env:UOK_LOCAL_SECRET_KEY_BASE = [Convert]::ToBase64String(
    [Security.Cryptography.RandomNumberGenerator]::GetBytes(64)
)
$env:UOK_LOCAL_METRICS_TOKEN = [Convert]::ToBase64String(
    [Security.Cryptography.RandomNumberGenerator]::GetBytes(48)
)
$env:UOK_APP_DB_PASSWORD = [Convert]::ToHexString(
    [Security.Cryptography.RandomNumberGenerator]::GetBytes(32)
).ToLowerInvariant()
if ([string]::IsNullOrWhiteSpace($env:UOK_DB_USER)) {
    $env:UOK_DB_USER = "uok_next"
}
if ([string]::IsNullOrWhiteSpace($env:UOK_DB_PASSWORD)) {
    $env:UOK_DB_PASSWORD = [Convert]::ToHexString(
        [Security.Cryptography.RandomNumberGenerator]::GetBytes(32)
    ).ToLowerInvariant()
}
if ($env:UOK_DB_PASSWORD -notmatch '^[A-Za-z0-9._~-]{32,128}$') {
    throw "UOK_DB_PASSWORD must contain 32 to 128 URL-safe characters"
}
if ([string]::IsNullOrWhiteSpace($env:UOK_DB_NAME)) {
    $env:UOK_DB_NAME = "uok_next_dev"
}
if ([string]::IsNullOrWhiteSpace($env:UOK_REVISION)) {
    $env:UOK_REVISION = (& git -C $repoRoot rev-parse HEAD).Trim()
}
if ($env:UOK_REVISION -notmatch '^[0-9a-f]{40}$') {
    throw "UOK_REVISION must resolve to a full lowercase Git revision"
}

$credentialPath = Get-UokCloneLocalCredentialPath -RepositoryRoot $repoRoot
Write-UokCloneLocalCredential -Path $credentialPath -Value $env:UOK_DB_PASSWORD

Push-Location $repoRoot
try {
    & podman compose -f (Join-Path $repoRoot "compose.yaml") up -d postgres
    if ($LASTEXITCODE -ne 0) {
        throw "The pinned local PostgreSQL dependency failed to start"
    }

    $databaseReady = $false
    foreach ($attempt in 1..15) {
        & podman compose -f (Join-Path $repoRoot "compose.yaml") exec -T postgres pg_isready `
            -U "${env:UOK_DB_USER}" -d "${env:UOK_DB_NAME}" 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $databaseReady = $true
            break
        }
        Start-Sleep -Seconds 2
    }
    if (-not $databaseReady) {
        throw "The pinned local PostgreSQL dependency did not become ready"
    }

    & podman compose -f (Join-Path $repoRoot "compose.yaml") exec -T postgres psql `
        -v ON_ERROR_STOP=1 `
        -v "admin_password=$($env:UOK_DB_PASSWORD)" `
        -U "${env:UOK_DB_USER}" `
        -d "${env:UOK_DB_NAME}" `
        -f /qualification/rotate_admin_password.sql
    if ($LASTEXITCODE -ne 0) {
        throw "The local PostgreSQL development credential could not be synchronized"
    }

    Write-Output "Local PostgreSQL is ready; the ACL-isolated clone credential is at $credentialPath"
}
finally {
    Pop-Location
}
