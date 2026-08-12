[CmdletBinding()]
param(
    [ValidateRange(1024, 65535)][int]$Port = 18089
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$composePath = Join-Path $repoRoot "compose.yaml"
. (Join-Path $PSScriptRoot "support\write_local_credential.ps1")

if (-not (Test-Path -LiteralPath $composePath -PathType Leaf)) {
    throw "compose.yaml was not found at the repository root"
}

function New-RandomToken {
    param([ValidateRange(32, 128)][int]$Bytes)

    [Convert]::ToBase64String((New-RandomBytes -Count $Bytes))
}

function New-RandomHex {
    param([ValidateRange(16, 64)][int]$Bytes)

    ([BitConverter]::ToString((New-RandomBytes -Count $Bytes))).Replace("-", "").ToLowerInvariant()
}

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

function Normalize-ImageId {
    param([Parameter(Mandatory = $true)][string]$Value)

    $Value -replace '^sha256:', ''
}

function Get-ContainerImageId {
    param([Parameter(Mandatory = $true)][string]$Container)

    $metadata = (& podman container inspect $Container | Out-String | ConvertFrom-Json)
    if ($LASTEXITCODE -ne 0 -or $metadata.Count -ne 1) {
        throw "Unable to inspect container $Container"
    }

    Normalize-ImageId -Value $metadata[0].Image
}

function Get-ReplicaRelease {
    param([Parameter(Mandatory = $true)][string]$Replica)

    $response = (& podman exec uok-next-proxy-1 wget -qO- "http://${Replica}:4000/api/v1/release" | Out-String)
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to query release identity directly from $Replica"
    }

    $response | ConvertFrom-Json
}

function Test-NativeCommand {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    # Windows PowerShell converts native stderr into error records. Expected
    # probe failures and Podman's external-provider banner must not bypass the
    # retry policy when the script otherwise runs fail-fast.
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "SilentlyContinue"
        & $FilePath @Arguments *> $null
        $succeeded = $LASTEXITCODE -eq 0
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    $succeeded
}

Push-Location $repoRoot
try {
    $revision = (& git rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $revision -notmatch '^[0-9a-f]{40}$') {
        throw "Unable to resolve the source revision"
    }

    $dirtyPaths = @(& git status --porcelain)
    if ($LASTEXITCODE -ne 0 -or $dirtyPaths.Count -gt 0) {
        throw "Local qualification requires a clean committed revision"
    }

    $env:UOK_LOCAL_SECRET_KEY_BASE = New-RandomToken -Bytes 64
    $env:UOK_LOCAL_METRICS_TOKEN = New-RandomToken -Bytes 48
    $env:UOK_APP_DB_PASSWORD = New-RandomHex -Bytes 32
    $env:UOK_OBJECT_STORE_ACCESS_KEY = New-RandomHex -Bytes 24
    $env:UOK_OBJECT_STORE_SECRET_KEY = New-RandomHex -Bytes 48
    $env:UOK_OBJECT_STORE_BUCKET = "uok-evidence"
    $env:UOK_OBJECT_STORE_PORT = "18333"
    if ([string]::IsNullOrWhiteSpace($env:UOK_DB_USER)) {
        $env:UOK_DB_USER = "uok_next"
    }
    if ([string]::IsNullOrWhiteSpace($env:UOK_DB_PASSWORD)) {
        $env:UOK_DB_PASSWORD = New-RandomHex -Bytes 32
    }
    if ($env:UOK_DB_PASSWORD -notmatch '^[A-Za-z0-9._~-]{32,128}$') {
        throw "UOK_DB_PASSWORD must contain 32 to 128 URL-safe characters"
    }
    if ([string]::IsNullOrWhiteSpace($env:UOK_DB_NAME)) {
        $env:UOK_DB_NAME = "uok_next_dev"
    }
    $env:UOK_HTTP_PORT = $Port.ToString()
    $env:UOK_REVISION = $revision
    $env:UOK_IMAGE_TAG = $revision.Substring(0, 12)

    $credentialPath = Get-UokCloneLocalCredentialPath -RepositoryRoot $repoRoot
    Write-UokCloneLocalCredential -Path $credentialPath -Value $env:UOK_DB_PASSWORD

    & podman compose -f $composePath build migrate
    if ($LASTEXITCODE -ne 0) {
        throw "The immutable release image build failed"
    }

    $imageReference = "localhost/uok-next:$($env:UOK_IMAGE_TAG)"
    $objectStorePolicy = Get-Content -LiteralPath (Join-Path $repoRoot "config/object_store_policy.json") -Raw |
        ConvertFrom-Json
    $objectStoreImageReference = [string]$objectStorePolicy.local_qualifier.image
    $imageMetadata = (& podman image inspect $imageReference | Out-String | ConvertFrom-Json)
    if ($LASTEXITCODE -ne 0 -or $imageMetadata.Count -ne 1) {
        throw "Unable to resolve the qualified image identity"
    }

    $imageId = Normalize-ImageId -Value $imageMetadata[0].Id
    $imageRevision = $imageMetadata[0].Labels.'org.opencontainers.image.revision'
    if ([string]::IsNullOrWhiteSpace($imageId) -or $imageRevision -ne $revision) {
        throw "The image identity label does not match the source revision"
    }

    & podman compose -f $composePath stop proxy app-a app-b object-store
    if ($LASTEXITCODE -ne 0) {
        throw "Existing local application containers could not be quiesced before role verification"
    }

    & podman compose -f $composePath up -d postgres
    if ($LASTEXITCODE -ne 0) {
        throw "The local qualification database failed to start"
    }

    $databaseReady = $false
    foreach ($attempt in 1..15) {
        $databaseProbeArguments = @(
            "compose", "-f", $composePath, "exec", "-T", "postgres", "pg_isready",
            "-U", $env:UOK_DB_USER, "-d", $env:UOK_DB_NAME
        )
        if (Test-NativeCommand -FilePath "podman" -Arguments $databaseProbeArguments) {
            $databaseReady = $true
            break
        }
        Start-Sleep -Seconds 2
    }
    if (-not $databaseReady) {
        throw "The local qualification database did not become ready"
    }

    & podman compose -f $composePath up -d --force-recreate object-store-init object-store
    if ($LASTEXITCODE -ne 0) {
        throw "The local qualification object store failed to start"
    }

    $objectStoreReady = $false
    foreach ($attempt in 1..20) {
        $objectStoreProbeArguments = @(
            "exec", "uok-next-object-store-1", "curl", "-fsS",
            "http://127.0.0.1:9333/cluster/status"
        )
        if (Test-NativeCommand -FilePath "podman" -Arguments $objectStoreProbeArguments) {
            $objectStoreReady = $true
            break
        }
        Start-Sleep -Seconds 2
    }
    if (-not $objectStoreReady) {
        throw "The local qualification object store did not become ready"
    }

    $objectStoreImageMetadata = (& podman image inspect $objectStoreImageReference |
            Out-String | ConvertFrom-Json)
    if ($LASTEXITCODE -ne 0 -or $objectStoreImageMetadata.Count -ne 1) {
        throw "Unable to resolve the approved object-store image identity"
    }
    $objectStoreImageId = Normalize-ImageId -Value $objectStoreImageMetadata[0].Id
    $runningObjectStoreImageId = Get-ContainerImageId -Container "uok-next-object-store-1"
    $objectStoreContainerMetadata = (& podman container inspect uok-next-object-store-1 |
            Out-String | ConvertFrom-Json)
    if ($LASTEXITCODE -ne 0 -or $objectStoreContainerMetadata.Count -ne 1 -or
        $runningObjectStoreImageId -ne $objectStoreImageId -or
        $objectStoreContainerMetadata[0].Config.User -ne "10001:10001") {
        throw "The object store is not running the approved non-root image identity"
    }

    & podman compose -f $composePath exec -T postgres psql `
        -v ON_ERROR_STOP=1 `
        -v "admin_password=$($env:UOK_DB_PASSWORD)" `
        -U "${env:UOK_DB_USER}" `
        -d "${env:UOK_DB_NAME}" `
        -f /qualification/rotate_admin_password.sql
    if ($LASTEXITCODE -ne 0) {
        throw "The local database owner credential could not be rotated"
    }

    & podman compose -f $composePath exec -T postgres psql `
        -v ON_ERROR_STOP=1 `
        -U "${env:UOK_DB_USER}" `
        -d "${env:UOK_DB_NAME}" `
        -f /database-baseline/verify_local_platform.sql
    if ($LASTEXITCODE -ne 0) {
        throw "The PostgreSQL 19 local platform baseline failed verification"
    }

    & podman compose -f $composePath exec -T postgres psql `
        -v ON_ERROR_STOP=1 `
        -v "app_password=$($env:UOK_APP_DB_PASSWORD)" `
        -U "${env:UOK_DB_USER}" `
        -d "${env:UOK_DB_NAME}" `
        -f /qualification/prepare_app_role.sql
    if ($LASTEXITCODE -ne 0) {
        throw "The least-privileged local application database role could not be prepared"
    }

    # Prove that reconciliation repairs a reused volume containing unsafe role
    # attributes, settings, and both directions of role membership. Application
    # containers remain stopped throughout this deliberately poisoned fixture.
    & podman compose -f $composePath exec -T postgres psql `
        -v ON_ERROR_STOP=1 `
        -U "${env:UOK_DB_USER}" `
        -d "${env:UOK_DB_NAME}" `
        -f /qualification/seed_unsafe_app_role_fixture.sql
    if ($LASTEXITCODE -ne 0) {
        throw "The unsafe persistent-role fixture could not be installed"
    }

    & podman exec -d uok-next-postgres-1 psql `
        -v ON_ERROR_STOP=1 `
        -U uok_qualification_poison `
        -d "${env:UOK_DB_NAME}" `
        -c "SET ROLE uok_app; SELECT pg_sleep(300)"
    if ($LASTEXITCODE -ne 0) {
        throw "The stale authorized-session fixture could not be started"
    }

    $staleSessionEstablished = $false
    foreach ($attempt in 1..10) {
        $staleSessionCount = (& podman compose -f $composePath exec -T postgres psql `
                -v ON_ERROR_STOP=1 `
                -U "${env:UOK_DB_USER}" `
                -d "${env:UOK_DB_NAME}" `
                -Atc "SELECT count(*) FROM pg_stat_activity WHERE datname = current_database() AND usename = 'uok_qualification_poison'" |
                Out-String).Trim()
        if ($LASTEXITCODE -ne 0) {
            throw "The stale authorized-session fixture could not be inspected"
        }
        if ($staleSessionCount -eq "1") {
            $staleSessionEstablished = $true
            break
        }
        Start-Sleep -Milliseconds 250
    }
    if (-not $staleSessionEstablished) {
        throw "The stale authorized-session fixture did not become active"
    }

    & podman compose -f $composePath exec -T postgres psql `
        -v ON_ERROR_STOP=1 `
        -v "app_password=$($env:UOK_APP_DB_PASSWORD)" `
        -U "${env:UOK_DB_USER}" `
        -d "${env:UOK_DB_NAME}" `
        -f /qualification/prepare_app_role.sql
    if ($LASTEXITCODE -ne 0) {
        throw "The runtime role did not reconcile deliberately unsafe persistent state"
    }

    $survivingStaleSessions = (& podman compose -f $composePath exec -T postgres psql `
            -v ON_ERROR_STOP=1 `
            -U "${env:UOK_DB_USER}" `
            -d "${env:UOK_DB_NAME}" `
            -Atc "SELECT count(*) FROM pg_stat_activity WHERE datname = current_database() AND usename = 'uok_qualification_poison'" |
            Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $survivingStaleSessions -ne "0") {
        throw "A stale runtime-authorized database session survived reconciliation"
    }

    & podman compose -f $composePath up -d migrate
    if ($LASTEXITCODE -ne 0) {
        throw "The local qualification migration failed to start"
    }

    $migrationExitCode = (& podman wait uok-next-migrate-1).Trim()
    if ($LASTEXITCODE -ne 0 -or $migrationExitCode -ne "0") {
        throw "The local qualification migration failed"
    }

    & podman compose -f $composePath exec -T postgres psql `
        -v ON_ERROR_STOP=1 `
        -U "${env:UOK_DB_USER}" `
        -d "${env:UOK_DB_NAME}" `
        -f /qualification/grant_app_role.sql
    if ($LASTEXITCODE -ne 0) {
        throw "The least-privileged application grants could not be applied"
    }

    & podman compose -f $composePath exec -T postgres psql `
        -v ON_ERROR_STOP=1 `
        -U "${env:UOK_DB_USER}" `
        -d "${env:UOK_DB_NAME}" `
        -f /qualification/verify_app_role.sql
    if ($LASTEXITCODE -ne 0) {
        throw "The local runtime database role failed least-privilege verification"
    }

    & podman compose -f $composePath exec -T postgres psql `
        -v ON_ERROR_STOP=1 `
        -U "${env:UOK_DB_USER}" `
        -d "${env:UOK_DB_NAME}" `
        -f /qualification/drop_unsafe_app_role_fixture.sql
    if ($LASTEXITCODE -ne 0) {
        throw "The unsafe persistent-role fixture could not be removed"
    }

    & podman compose -f $composePath up -d --force-recreate app-a app-b
    if ($LASTEXITCODE -ne 0) {
        throw "The local qualification application replicas failed to start"
    }

    & podman compose -f $composePath up -d --force-recreate proxy
    if ($LASTEXITCODE -ne 0) {
        throw "The local qualification proxy failed to start"
    }

    $baseUri = "http://127.0.0.1:$Port/api/v1"
    $ready = $null
    foreach ($attempt in 1..15) {
        try {
            $candidate = Invoke-RestMethod -Uri "$baseUri/health/ready" -TimeoutSec 5
            if ($candidate.status -eq "ready") {
                $ready = $candidate
                break
            }
        }
        catch {
            Start-Sleep -Seconds 2
        }
    }
    if ($null -eq $ready) {
        throw "The local qualification endpoint did not become ready"
    }

    $appAImageId = Get-ContainerImageId -Container "uok-next-app-a-1"
    $appBImageId = Get-ContainerImageId -Container "uok-next-app-b-1"
    if ($appAImageId -ne $imageId -or $appBImageId -ne $imageId) {
        throw "One or more application replicas are not running the qualified immutable image"
    }

    $appARelease = Get-ReplicaRelease -Replica "app-a"
    $appBRelease = Get-ReplicaRelease -Replica "app-b"
    if ($appARelease.revision -ne $revision -or $appBRelease.revision -ne $revision) {
        throw "One or more application replicas report the wrong compiled revision"
    }

    $release = Invoke-RestMethod -Uri "$baseUri/release" -TimeoutSec 10
    $headers = @{ Authorization = "Bearer $($env:UOK_LOCAL_METRICS_TOKEN)" }
    $metrics = Invoke-WebRequest -Uri "$baseUri/metrics" -Headers $headers `
        -TimeoutSec 10 -UseBasicParsing

    if ($ready.status -ne "ready" -or $release.revision -ne $revision) {
        throw "The deployed release identity or readiness response is incorrect"
    }
    if ($metrics.StatusCode -ne 200 -or $metrics.Content -notmatch 'uok_next_repo_query') {
        throw "The authenticated metrics endpoint did not expose repository telemetry"
    }

    $objectStoreQualification = (& podman exec uok-next-app-a-1 /app/bin/uok_next rpc `
            "UokNext.Release.ObjectStoreQualification.run!()" | Out-String)
    if ($LASTEXITCODE -ne 0 -or
        $objectStoreQualification -notmatch
            'Object-store create-only, integrity, and deletion qualification passed') {
        throw "The immutable bounded object-store qualification failed"
    }

    & podman compose -f $composePath stop app-a
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to stop the first application replica for failover qualification"
    }

    try {
        # Allow the configured health-check failure window to close, then make
        # every verification request fail closed; no retry masks a bad route.
        Start-Sleep -Seconds 5

        foreach ($attempt in 1..4) {
            $failoverReady = Invoke-RestMethod `
                -Uri "$baseUri/health/ready" -TimeoutSec 5 -DisableKeepAlive
            $failoverRelease = Invoke-RestMethod `
                -Uri "$baseUri/release" -TimeoutSec 5 -DisableKeepAlive

            if ($failoverReady.status -ne "ready" -or $failoverRelease.revision -ne $revision) {
                throw "The surviving application replica did not remain ready on the qualified revision"
            }
        }
    }
    finally {
        & podman compose -f $composePath up -d app-a
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "The stopped application replica could not be restarted automatically"
        }
    }

    [pscustomobject]@{
        endpoint = $baseUri
        revision = $revision
        readiness = $ready.status
        image = $imageReference
        image_id = $imageId
        app_a_image_id = $appAImageId
        app_b_image_id = $appBImageId
        object_store_image = $objectStoreImageReference
        object_store_image_id = $objectStoreImageId
        object_store_round_trip = "create, collision rejection, read-after-write digest verification, and delete passed"
        replicas = 2
        single_replica_failover = "4 readiness and release probes passed"
    } | ConvertTo-Json
}
finally {
    Pop-Location
}
