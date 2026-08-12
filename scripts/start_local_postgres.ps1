[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "support\write_local_credential.ps1")

function New-RandomBytes {
    param([ValidateRange(16, 128)][int]$Count)

    [byte[]]$bytes = New-Object byte[] $Count
    $generator = [Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $generator.GetBytes($bytes)
    }
    finally {
        $generator.Dispose()
    }
    return $bytes
}

$env:UOK_LOCAL_SECRET_KEY_BASE = [Convert]::ToBase64String((New-RandomBytes -Count 64))
$env:UOK_LOCAL_METRICS_TOKEN = [Convert]::ToBase64String((New-RandomBytes -Count 48))
$env:UOK_LOCAL_ACCESS_CODE = ([BitConverter]::ToString((New-RandomBytes -Count 32))).Replace("-", "").ToLowerInvariant()
$env:UOK_LOCAL_TENANT_ID = [Guid]::NewGuid().ToString()
$env:UOK_LOCAL_ACTOR_ID = [Guid]::NewGuid().ToString()
$env:UOK_APP_DB_PASSWORD = ([BitConverter]::ToString((New-RandomBytes -Count 32))).Replace("-", "").ToLowerInvariant()
if ([string]::IsNullOrWhiteSpace($env:UOK_DB_USER)) {
    $env:UOK_DB_USER = "uok_next"
}
if ([string]::IsNullOrWhiteSpace($env:UOK_DB_PASSWORD)) {
    $env:UOK_DB_PASSWORD = ([BitConverter]::ToString((New-RandomBytes -Count 32))).Replace("-", "").ToLowerInvariant()
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

    & podman compose -f (Join-Path $repoRoot "compose.yaml") exec -T postgres psql `
        -v ON_ERROR_STOP=1 `
        -U "${env:UOK_DB_USER}" `
        -d "${env:UOK_DB_NAME}" `
        -f /database-baseline/verify_local_platform.sql
    if ($LASTEXITCODE -ne 0) {
        throw "The local PostgreSQL 19 platform baseline failed verification"
    }

    Write-Output "Local PostgreSQL 19 is ready; the ACL-isolated clone credential is at $credentialPath"
}
finally {
    Pop-Location
}
