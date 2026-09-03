[CmdletBinding()]
param(
    [ValidateRange(1024, 65535)][int]$Port = 18089
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$composePath = Join-Path $repoRoot "compose.yaml"
. (Join-Path $PSScriptRoot "support\write_local_credential.ps1")

# Windows PowerShell does not load this assembly until a System.Net.Http type is
# first resolved. Load it explicitly so the multipart evidence qualifier uses
# the same script path under Windows PowerShell and PowerShell 7.
Add-Type -AssemblyName System.Net.Http

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

function Invoke-Gate3EvidenceUpload {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$Token,
        [Parameter(Mandatory = $true)][string]$IdempotencyKey,
        [Parameter(Mandatory = $true)][string]$EvidenceId,
        [Parameter(Mandatory = $true)][int]$ExpectedVersion,
        [string]$Reason = "Attach qualification registration evidence"
    )

    $client = [Net.Http.HttpClient]::new()
    $form = [Net.Http.MultipartFormDataContent]::new()
    try {
        $client.DefaultRequestHeaders.Authorization =
            [Net.Http.Headers.AuthenticationHeaderValue]::new("Bearer", $Token)
        $client.DefaultRequestHeaders.Add("Idempotency-Key", $IdempotencyKey)
        $form.Add([Net.Http.StringContent]::new($EvidenceId), "evidence_id")
        $form.Add([Net.Http.StringContent]::new($ExpectedVersion.ToString()), "expected_version")
        $form.Add([Net.Http.StringContent]::new("confidential"), "classification")
        $form.Add(
            [Net.Http.StringContent]::new($Reason),
            "reason"
        )
        $bytes = [Text.Encoding]::UTF8.GetBytes(
            "UOK Next Gate 3 qualification evidence $EvidenceId"
        )
        $file = [Net.Http.ByteArrayContent]::new($bytes)
        $file.Headers.ContentType = [Net.Http.Headers.MediaTypeHeaderValue]::new("text/plain")
        $form.Add($file, "file", "qualification-evidence.txt")

        $response = $client.PostAsync($Uri, $form).GetAwaiter().GetResult()
        $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        if (-not $response.IsSuccessStatusCode) {
            throw "The Gate 3 evidence command was rejected with HTTP $([int]$response.StatusCode)"
        }
        $body | ConvertFrom-Json
    }
    finally {
        $form.Dispose()
        $client.Dispose()
    }
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
    $env:UOK_OUTBOX_DB_PASSWORD = New-RandomHex -Bytes 32
    $env:UOK_OBJECT_STORE_ACCESS_KEY = New-RandomHex -Bytes 24
    $env:UOK_OBJECT_STORE_SECRET_KEY = New-RandomHex -Bytes 48
    $env:UOK_OBJECT_STORE_BUCKET = "uok-evidence"
    $env:UOK_OBJECT_STORE_PORT = "18333"

    $identityCredentialPath = Get-UokCloneLocalCredentialPath `
        -RepositoryRoot $repoRoot -CredentialName "uok-local-identity.json"
    $identityCredential = Read-UokCloneLocalCredential -Path $identityCredentialPath
    if ([string]::IsNullOrWhiteSpace($identityCredential)) {
        $identity = [ordered]@{
            tenant_id = [Guid]::NewGuid().ToString()
            actor_id = [Guid]::NewGuid().ToString()
            access_code = New-RandomHex -Bytes 32
        }
        Write-UokCloneLocalCredential -Path $identityCredentialPath `
            -Value ($identity | ConvertTo-Json -Compress)
    }
    else {
        try {
            $identity = $identityCredential | ConvertFrom-Json
        }
        catch {
            throw "The clone-local qualification identity is malformed"
        }
    }
    if ($identity.tenant_id -notmatch '^[0-9a-fA-F-]{36}$' -or
        $identity.actor_id -notmatch '^[0-9a-fA-F-]{36}$' -or
        $identity.access_code -notmatch '^[a-f0-9]{64}$') {
        throw "The clone-local qualification identity is invalid"
    }
    $env:UOK_LOCAL_TENANT_ID = [Guid]::Parse($identity.tenant_id).ToString()
    $env:UOK_LOCAL_ACTOR_ID = [Guid]::Parse($identity.actor_id).ToString()
    $env:UOK_LOCAL_ACCESS_CODE = [string]$identity.access_code
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

    & podman compose -f $composePath exec -T postgres psql `
        -v ON_ERROR_STOP=1 `
        -v "outbox_password=$($env:UOK_OUTBOX_DB_PASSWORD)" `
        -U "${env:UOK_DB_USER}" `
        -d "${env:UOK_DB_NAME}" `
        -f /qualification/prepare_outbox_role.sql
    if ($LASTEXITCODE -ne 0) {
        throw "The least-privileged durable-work database role could not be prepared"
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
        -f /qualification/grant_outbox_role.sql
    if ($LASTEXITCODE -ne 0) {
        throw "The least-privileged durable-work grants could not be applied"
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
        -f /qualification/verify_outbox_role.sql
    if ($LASTEXITCODE -ne 0) {
        throw "The durable-work database role failed least-privilege verification"
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

    $baseOrigin = "http://127.0.0.1:$Port"
    $baseUri = "$baseOrigin/api/v1"
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

    $shell = Invoke-WebRequest -Uri "$baseOrigin/" -MaximumRedirection 3 `
        -TimeoutSec 10 -UseBasicParsing
    if ($shell.StatusCode -ne 200 -or $shell.Content -notmatch '<title>UOK Next</title>') {
        throw "The local qualification browser shell was not reachable through the proxy"
    }

    $sessionBody = @{ access_code = $env:UOK_LOCAL_ACCESS_CODE } | ConvertTo-Json -Compress
    $session = Invoke-RestMethod -Uri "$baseUri/session" -Method Post `
        -ContentType "application/json" -Body $sessionBody -TimeoutSec 10
    $accessToken = [string]$session.data.access_token
    if ($accessToken.Length -lt 32 -or
        $session.data.identity.tenant_id -ne $env:UOK_LOCAL_TENANT_ID) {
        throw "The local qualification session did not bind the configured tenant"
    }

    $flowId = [Guid]::NewGuid().ToString()
    $authHeaders = @{
        Authorization = "Bearer $accessToken"
        "Idempotency-Key" = [Guid]::NewGuid().ToString()
    }
    $partyBody = @{
        stable_identifier = "qualification-$flowId"
        legal_name = "Gate 3 Qualification Party"
        country_code = "GH"
        party_kind = "organization"
        reason = "Prove the complete governed onboarding journey"
    } | ConvertTo-Json -Compress
    $party = Invoke-RestMethod -Uri "$baseUri/parties" -Method Post -Headers $authHeaders `
        -ContentType "application/json" -Body $partyBody -TimeoutSec 10

    $evidenceId = [Guid]::NewGuid().ToString()
    $evidenceKey = [Guid]::NewGuid().ToString()
    $evidenced = Invoke-Gate3EvidenceUpload `
        -Uri "$baseUri/parties/$($party.data.id)/evidence" `
        -Token $accessToken -IdempotencyKey $evidenceKey `
        -EvidenceId $evidenceId -ExpectedVersion ([int]$party.data.lock_version)
    $evidenceReplay = Invoke-Gate3EvidenceUpload `
        -Uri "$baseUri/parties/$($party.data.id)/evidence" `
        -Token $accessToken -IdempotencyKey $evidenceKey `
        -EvidenceId $evidenceId -ExpectedVersion ([int]$party.data.lock_version)

    $readHeaders = @{ Authorization = "Bearer $accessToken" }
    $tasks = Invoke-RestMethod -Uri "$baseUri/review-tasks" -Headers $readHeaders -TimeoutSec 10
    $task = @($tasks.data | Where-Object subject_id -eq $party.data.id)
    if ($task.Count -ne 1 -or $evidenced.data.status -ne "evidence_submitted" -or
        $evidenceReplay.data.review_task.id -ne $evidenced.data.review_task.id) {
        throw "The Gate 3 evidence or exact-task replay contract failed"
    }

    $decisionHeaders = @{
        Authorization = "Bearer $accessToken"
        "Idempotency-Key" = [Guid]::NewGuid().ToString()
    }
    $decisionBody = @{
        decision = "approve"
        reason = "Qualification evidence passed governed review"
        task_id = $task[0].id
        expected_version = [int]$evidenced.data.lock_version
    } | ConvertTo-Json -Compress
    $approved = Invoke-RestMethod -Uri "$baseUri/parties/$($party.data.id)/decision" `
        -Method Post -Headers $decisionHeaders -ContentType "application/json" `
        -Body $decisionBody -TimeoutSec 10
    $partyDetail = Invoke-RestMethod -Uri "$baseUri/parties/$($party.data.id)" `
        -Headers $readHeaders -TimeoutSec 10

    if ($approved.data.status -ne "approved" -or $partyDetail.data.status -ne "approved" -or
        @($partyDetail.data.evidence_objects).Count -ne 1 -or
        $partyDetail.data.evidence_objects[0].state -ne "verified") {
        throw "The Gate 3 party-onboarding journey did not reach verified approval"
    }

    $secondPartyHeaders = @{
        Authorization = "Bearer $accessToken"
        "Idempotency-Key" = [Guid]::NewGuid().ToString()
    }
    $secondPartyBody = @{
        stable_identifier = "qualification-second-$flowId"
        legal_name = "Gate 3 Qualification Supplier Two"
        country_code = "GH"
        party_kind = "organization"
        reason = "Create a second attributable RFQ supplier"
    } | ConvertTo-Json -Compress
    $secondParty = Invoke-RestMethod -Uri "$baseUri/parties" -Method Post `
        -Headers $secondPartyHeaders -ContentType "application/json" `
        -Body $secondPartyBody -TimeoutSec 10
    $secondPartyEvidence = Invoke-Gate3EvidenceUpload `
        -Uri "$baseUri/parties/$($secondParty.data.id)/evidence" `
        -Token $accessToken -IdempotencyKey ([Guid]::NewGuid().ToString()) `
        -EvidenceId ([Guid]::NewGuid().ToString()) `
        -ExpectedVersion ([int]$secondParty.data.lock_version) `
        -Reason "Attach second supplier qualification evidence"
    $secondPartyTasks = Invoke-RestMethod -Uri "$baseUri/review-tasks" `
        -Headers $readHeaders -TimeoutSec 10
    $secondPartyTask = @($secondPartyTasks.data | Where-Object subject_id -eq $secondParty.data.id)
    if ($secondPartyTask.Count -ne 1) {
        throw "The second supplier exact review task was not opened"
    }
    $secondPartyDecisionBody = @{
        decision = "approve"
        reason = "Second supplier evidence passed governed review"
        task_id = $secondPartyTask[0].id
        expected_version = [int]$secondPartyEvidence.data.lock_version
    } | ConvertTo-Json -Compress
    $secondPartyApproved = Invoke-RestMethod `
        -Uri "$baseUri/parties/$($secondParty.data.id)/decision" -Method Post `
        -Headers @{
            Authorization = "Bearer $accessToken"
            "Idempotency-Key" = [Guid]::NewGuid().ToString()
        } -ContentType "application/json" -Body $secondPartyDecisionBody -TimeoutSec 10
    if ($secondPartyApproved.data.status -ne "approved") {
        throw "The second RFQ supplier did not reach governed approval"
    }

    $productHeaders = @{
        Authorization = "Bearer $accessToken"
        "Idempotency-Key" = [Guid]::NewGuid().ToString()
    }
    $productBody = @{
        stable_identifier = "product-$flowId"
        name = "Gate 3 Qualification Product"
        product_kind = "commodity"
        base_unit_code = "MT"
        reason = "Prove governed product authority"
    } | ConvertTo-Json -Compress
    $product = Invoke-RestMethod -Uri "$baseUri/products" -Method Post `
        -Headers $productHeaders -ContentType "application/json" `
        -Body $productBody -TimeoutSec 10

    $locations = @()
    foreach ($location in @(
            @{ suffix = "origin"; name = "Qualification Origin"; country = "GH" },
            @{ suffix = "destination"; name = "Qualification Destination"; country = "GB" }
        )) {
        $locationHeaders = @{
            Authorization = "Bearer $accessToken"
            "Idempotency-Key" = [Guid]::NewGuid().ToString()
        }
        $locationBody = @{
            stable_identifier = "$($location.suffix)-$flowId"
            name = $location.name
            country_code = $location.country
            location_kind = "port"
            reason = "Prove governed route location authority"
        } | ConvertTo-Json -Compress
        $createdLocation = Invoke-RestMethod -Uri "$baseUri/locations" -Method Post `
            -Headers $locationHeaders -ContentType "application/json" `
            -Body $locationBody -TimeoutSec 10
        $locations += $createdLocation.data
    }

    $laneHeaders = @{
        Authorization = "Bearer $accessToken"
        "Idempotency-Key" = [Guid]::NewGuid().ToString()
    }
    $laneBody = @{
        stable_identifier = "lane-$flowId"
        name = "Gate 3 Qualification Sourcing Lane"
        supplier_party_id = $party.data.id
        product_id = $product.data.id
        origin_location_id = $locations[0].id
        destination_location_id = $locations[1].id
        reason = "Prove governed sourcing authority"
    } | ConvertTo-Json -Compress
    $lane = Invoke-RestMethod -Uri "$baseUri/sourcing-lanes" -Method Post `
        -Headers $laneHeaders -ContentType "application/json" -Body $laneBody -TimeoutSec 10

    $laneEvidenceId = [Guid]::NewGuid().ToString()
    $laneEvidenceKey = [Guid]::NewGuid().ToString()
    $laneEvidenced = Invoke-Gate3EvidenceUpload `
        -Uri "$baseUri/sourcing-lanes/$($lane.data.id)/evidence" `
        -Token $accessToken -IdempotencyKey $laneEvidenceKey `
        -EvidenceId $laneEvidenceId -ExpectedVersion ([int]$lane.data.lock_version) `
        -Reason "Attach qualification sourcing authority evidence"
    $laneEvidenceReplay = Invoke-Gate3EvidenceUpload `
        -Uri "$baseUri/sourcing-lanes/$($lane.data.id)/evidence" `
        -Token $accessToken -IdempotencyKey $laneEvidenceKey `
        -EvidenceId $laneEvidenceId -ExpectedVersion ([int]$lane.data.lock_version) `
        -Reason "Attach qualification sourcing authority evidence"

    $laneTasks = Invoke-RestMethod -Uri "$baseUri/review-tasks" `
        -Headers $readHeaders -TimeoutSec 10
    $laneTask = @($laneTasks.data | Where-Object subject_id -eq $lane.data.id)
    if ($laneTask.Count -ne 1 -or $laneEvidenced.data.status -ne "evidence_submitted" -or
        $laneEvidenceReplay.data.review_task.id -ne $laneEvidenced.data.review_task.id) {
        throw "The Gate 3 sourcing evidence or exact-task replay contract failed"
    }

    $laneDecisionHeaders = @{
        Authorization = "Bearer $accessToken"
        "Idempotency-Key" = [Guid]::NewGuid().ToString()
    }
    $laneDecisionBody = @{
        decision = "approve"
        reason = "Qualification sourcing evidence passed governed review"
        task_id = $laneTask[0].id
        expected_version = [int]$laneEvidenced.data.lock_version
    } | ConvertTo-Json -Compress
    $laneApproved = Invoke-RestMethod `
        -Uri "$baseUri/sourcing-lanes/$($lane.data.id)/decision" `
        -Method Post -Headers $laneDecisionHeaders -ContentType "application/json" `
        -Body $laneDecisionBody -TimeoutSec 10
    $laneDetail = Invoke-RestMethod -Uri "$baseUri/sourcing-lanes/$($lane.data.id)" `
        -Headers $readHeaders -TimeoutSec 10

    if ($laneApproved.data.status -ne "approved" -or $laneDetail.data.status -ne "approved" -or
        @($laneDetail.data.evidence_objects).Count -ne 1 -or
        $laneDetail.data.supplier_party_id -ne $party.data.id -or
        $laneDetail.data.product_id -ne $product.data.id) {
        throw "The Gate 3 product-sourcing journey did not reach verified approval"
    }

    $requisitionBody = @{
        stable_identifier = "requisition-$flowId"
        sourcing_lane_id = $lane.data.id
        quantity = "25"
        unit_code = "MT"
        required_by = [DateTime]::UtcNow.AddDays(30).ToString("yyyy-MM-dd")
        reason = "Prove a version-bound purchasing requirement"
    } | ConvertTo-Json -Compress
    $requisition = Invoke-RestMethod -Uri "$baseUri/purchase-requisitions" -Method Post `
        -Headers @{
            Authorization = "Bearer $accessToken"
            "Idempotency-Key" = [Guid]::NewGuid().ToString()
        } -ContentType "application/json" -Body $requisitionBody -TimeoutSec 10

    $rfqBody = @{
        stable_identifier = "rfq-$flowId"
        requisition_id = $requisition.data.id
        expected_version = [int]$requisition.data.lock_version
        settlement_currency_code = "USD"
        response_deadline = [DateTime]::UtcNow.AddDays(7).ToString("o")
        supplier_party_ids = @($party.data.id, $secondParty.data.id)
        reason = "Prove approved supplier invitation authority"
    } | ConvertTo-Json -Depth 4 -Compress
    $rfq = Invoke-RestMethod -Uri "$baseUri/rfqs" -Method Post `
        -Headers @{
            Authorization = "Bearer $accessToken"
            "Idempotency-Key" = [Guid]::NewGuid().ToString()
        } -ContentType "application/json" -Body $rfqBody -TimeoutSec 10

    $submittedQuotes = @()
    foreach ($offer in @(
            @{ supplier_id = $party.data.id; price = "100"; days = 14; suffix = "first" },
            @{ supplier_id = $secondParty.data.id; price = "90"; days = 21; suffix = "second" }
        )) {
        $quoteBody = @{
            stable_identifier = "quote-$($offer.suffix)-$flowId"
            rfq_id = $rfq.data.id
            supplier_party_id = $offer.supplier_id
            quoted_quantity = "25"
            unit_price = $offer.price
            currency_code = "USD"
            delivery_days = $offer.days
            reason = "Record an attributable qualification quote"
        } | ConvertTo-Json -Compress
        $quote = Invoke-RestMethod -Uri "$baseUri/supplier-quotes" -Method Post `
            -Headers @{
                Authorization = "Bearer $accessToken"
                "Idempotency-Key" = [Guid]::NewGuid().ToString()
            } -ContentType "application/json" -Body $quoteBody -TimeoutSec 10
        $submittedQuote = Invoke-Gate3EvidenceUpload `
            -Uri "$baseUri/supplier-quotes/$($quote.data.id)/evidence" `
            -Token $accessToken -IdempotencyKey ([Guid]::NewGuid().ToString()) `
            -EvidenceId ([Guid]::NewGuid().ToString()) `
            -ExpectedVersion ([int]$quote.data.lock_version) `
            -Reason "Attach attributable quote source evidence"
        $submittedQuotes += $submittedQuote.data
    }

    $comparisonBody = @{
        stable_identifier = "comparison-$flowId"
        rfq_id = $rfq.data.id
        expected_version = [int]$rfq.data.lock_version
        reason = "Prove deterministic quote comparison"
    } | ConvertTo-Json -Compress
    $comparison = Invoke-RestMethod -Uri "$baseUri/quote-comparisons" -Method Post `
        -Headers @{
            Authorization = "Bearer $accessToken"
            "Idempotency-Key" = [Guid]::NewGuid().ToString()
        } -ContentType "application/json" -Body $comparisonBody -TimeoutSec 10
    $comparisonTasks = Invoke-RestMethod -Uri "$baseUri/review-tasks" `
        -Headers $readHeaders -TimeoutSec 10
    $comparisonTask = @($comparisonTasks.data | Where-Object subject_id -eq $comparison.data.id)
    if ($comparisonTask.Count -ne 1 -or $comparison.data.recommended_quote_id -ne $submittedQuotes[1].id -or
        @($comparison.data.ranking_snapshot.ranking).Count -ne 2) {
        throw "The deterministic quote comparison or exact review task failed"
    }

    $comparisonDecisionBody = @{
        decision = "approve"
        reason = "Attributable quote comparison passed governed review"
        task_id = $comparisonTask[0].id
        expected_version = [int]$comparison.data.lock_version
    } | ConvertTo-Json -Compress
    $comparisonApproved = Invoke-RestMethod `
        -Uri "$baseUri/quote-comparisons/$($comparison.data.id)/decision" -Method Post `
        -Headers @{
            Authorization = "Bearer $accessToken"
            "Idempotency-Key" = [Guid]::NewGuid().ToString()
        } -ContentType "application/json" -Body $comparisonDecisionBody -TimeoutSec 10
    if ($comparisonApproved.data.status -ne "approved") {
        throw "The Gate 3 quote comparison did not reach exact human approval"
    }

    $proposalBody = @{
        stable_identifier = "commitment-proposal-$flowId"
        quote_comparison_id = $comparisonApproved.data.id
        expected_comparison_version = [int]$comparisonApproved.data.lock_version
        reason = "Prove a source-derived non-binding purchase commitment proposal"
    } | ConvertTo-Json -Compress
    $proposal = Invoke-RestMethod -Uri "$baseUri/purchase-commitment-proposals" -Method Post `
        -Headers @{
            Authorization = "Bearer $accessToken"
            "Idempotency-Key" = [Guid]::NewGuid().ToString()
        } -ContentType "application/json" -Body $proposalBody -TimeoutSec 10
    if ($proposal.data.status -ne "draft" -or
        $proposal.data.selected_quote_id -ne $comparisonApproved.data.recommended_quote_id -or
        $proposal.data.source_snapshot.quote_comparison_id -ne $comparisonApproved.data.id -or
        $proposal.data.commitment_created -or $proposal.data.external_effect_created) {
        throw "The source-derived purchase commitment proposal boundary failed"
    }

    $proposalEvidenced = Invoke-Gate3EvidenceUpload `
        -Uri "$baseUri/purchase-commitment-proposals/$($proposal.data.id)/evidence" `
        -Token $accessToken -IdempotencyKey ([Guid]::NewGuid().ToString()) `
        -EvidenceId ([Guid]::NewGuid().ToString()) `
        -ExpectedVersion ([int]$proposal.data.lock_version) `
        -Reason "Attach reviewed internal commitment rationale"
    $proposalTasks = Invoke-RestMethod -Uri "$baseUri/review-tasks" `
        -Headers $readHeaders -TimeoutSec 10
    $proposalTask = @($proposalTasks.data | Where-Object subject_id -eq $proposal.data.id)
    if ($proposalEvidenced.data.status -ne "awaiting_review" -or $proposalTask.Count -ne 1 -or
        $proposalTask[0].id -ne $proposalEvidenced.data.review_task.id) {
        throw "The purchase commitment evidence or exact-task contract failed"
    }

    $proposalDecisionBody = @{
        decision = "approve"
        reason = "Approve the exact source-bound internal proposal"
        task_id = $proposalTask[0].id
        expected_version = [int]$proposalEvidenced.data.lock_version
    } | ConvertTo-Json -Compress
    $proposalApproved = Invoke-RestMethod `
        -Uri "$baseUri/purchase-commitment-proposals/$($proposal.data.id)/decision" -Method Post `
        -Headers @{
            Authorization = "Bearer $accessToken"
            "Idempotency-Key" = [Guid]::NewGuid().ToString()
        } -ContentType "application/json" -Body $proposalDecisionBody -TimeoutSec 10
    $proposals = Invoke-RestMethod -Uri "$baseUri/purchase-commitment-proposals?limit=100" `
        -Headers $readHeaders -TimeoutSec 10
    $qualifiedProposal = @($proposals.data | Where-Object id -eq $proposal.data.id)
    if ($proposalApproved.data.status -ne "approved" -or $qualifiedProposal.Count -ne 1 -or
        $qualifiedProposal[0].status -ne "approved" -or
        $qualifiedProposal[0].source_snapshot.selected_quote_id -ne $submittedQuotes[1].id -or
        $proposalApproved.data.commitment_created -or $proposalApproved.data.external_effect_created) {
        throw "The purchase commitment proposal did not reach safe exact approval"
    }

    $readinessBody = @{
        stable_identifier = "shipment-readiness-$flowId"
        purchase_commitment_proposal_id = $proposalApproved.data.id
        expected_proposal_version = [int]$proposalApproved.data.lock_version
        reason = "Open one source-bound non-executing shipment-readiness gate"
    } | ConvertTo-Json -Compress
    $readiness = Invoke-RestMethod -Uri "$baseUri/shipment-readiness-cases" -Method Post `
        -Headers @{
            Authorization = "Bearer $accessToken"
            "Idempotency-Key" = [Guid]::NewGuid().ToString()
        } -ContentType "application/json" -Body $readinessBody -TimeoutSec 10
    $pendingReadinessChecks = @(
        $readiness.data.checklist_snapshot.checks | Where-Object status -eq "pending"
    )
    if ($readiness.data.status -ne "draft" -or $pendingReadinessChecks.Count -ne 1 -or
        $pendingReadinessChecks[0].code -ne "verified_operational_readiness_evidence" -or
        $readiness.data.source_snapshot.purchase_commitment_proposal_id -ne $proposal.data.id -or
        $readiness.data.shipment_created -or $readiness.data.dispatch_created -or
        $readiness.data.inventory_effect_created -or $readiness.data.finance_effect_created -or
        $readiness.data.external_effect_created) {
        throw "The source-derived shipment-readiness boundary failed"
    }

    $readinessEvidenced = Invoke-Gate3EvidenceUpload `
        -Uri "$baseUri/shipment-readiness-cases/$($readiness.data.id)/evidence" `
        -Token $accessToken -IdempotencyKey ([Guid]::NewGuid().ToString()) `
        -EvidenceId ([Guid]::NewGuid().ToString()) `
        -ExpectedVersion ([int]$readiness.data.lock_version) `
        -Reason "Attach the reviewed operational-readiness evidence bundle"
    $readinessTasks = Invoke-RestMethod -Uri "$baseUri/review-tasks" `
        -Headers $readHeaders -TimeoutSec 10
    $readinessTask = @($readinessTasks.data | Where-Object subject_id -eq $readiness.data.id)
    $incompleteReadinessChecks = @(
        $readinessEvidenced.data.checklist_snapshot.checks | Where-Object status -ne "passed"
    )
    if ($readinessEvidenced.data.status -ne "awaiting_review" -or
        $readinessTask.Count -ne 1 -or $incompleteReadinessChecks.Count -ne 0 -or
        $readinessTask[0].id -ne $readinessEvidenced.data.review_task.id) {
        throw "The shipment-readiness evidence, checklist, or exact-task contract failed"
    }

    $readinessDecisionBody = @{
        decision = "go"
        reason = "Record exact human GO without releasing downstream execution"
        task_id = $readinessTask[0].id
        expected_version = [int]$readinessEvidenced.data.lock_version
    } | ConvertTo-Json -Compress
    $readinessGo = Invoke-RestMethod `
        -Uri "$baseUri/shipment-readiness-cases/$($readiness.data.id)/decision" -Method Post `
        -Headers @{
            Authorization = "Bearer $accessToken"
            "Idempotency-Key" = [Guid]::NewGuid().ToString()
        } -ContentType "application/json" -Body $readinessDecisionBody -TimeoutSec 10
    $readinessCases = Invoke-RestMethod -Uri "$baseUri/shipment-readiness-cases?limit=100" `
        -Headers $readHeaders -TimeoutSec 10
    $qualifiedReadiness = @($readinessCases.data | Where-Object id -eq $readiness.data.id)
    if ($readinessGo.data.status -ne "go" -or $qualifiedReadiness.Count -ne 1 -or
        $qualifiedReadiness[0].status -ne "go" -or $readinessGo.data.shipment_created -or
        $readinessGo.data.dispatch_created -or $readinessGo.data.inventory_effect_created -or
        $readinessGo.data.finance_effect_created -or $readinessGo.data.external_effect_created) {
        throw "The shipment-readiness case did not reach safe exact GO"
    }

    $operationalReportUri = "$baseUri/operational-reports/$($readiness.data.id)" +
        "?expected_version=$([int]$readinessGo.data.lock_version)"
    $operationalReport = Invoke-RestMethod -Uri $operationalReportUri `
        -Headers $readHeaders -TimeoutSec 10
    $repeatedReport = Invoke-RestMethod -Uri $operationalReportUri `
        -Headers $readHeaders -TimeoutSec 10
    $reportAuditLeaks = @(
        $operationalReport.data.audit_events | Where-Object {
            $_.PSObject.Properties.Name -contains "metadata"
        }
    )
    $reportDeliveryLeaks = @(
        $operationalReport.data.delivery_events | Where-Object {
            $_.PSObject.Properties.Name -contains "payload"
        }
    )
    if ($operationalReport.data.outcome -ne "ready" -or
        $operationalReport.data.grain.id -ne $readiness.data.id -or
        [int]$operationalReport.data.grain.version -ne [int]$readinessGo.data.lock_version -or
        $operationalReport.data.stages.Count -ne 6 -or
        $operationalReport.data.evidence_lineage.Count -ne 5 -or
        $operationalReport.data.audit_events.Count -lt 1 -or
        $operationalReport.data.delivery_events.Count -lt 1 -or
        $reportAuditLeaks.Count -ne 0 -or $reportDeliveryLeaks.Count -ne 0 -or
        $operationalReport.data.freshness.mode -ne "live_repeatable_read" -or
        [int]$operationalReport.data.freshness.maximum_staleness_seconds -ne 0 -or
        $operationalReport.data.reconciliation.status -ne "reconciled" -or
        $operationalReport.data.reconciliation.projection_sha256 -ne
            $operationalReport.data.projection_id -or
        $repeatedReport.data.projection_id -ne $operationalReport.data.projection_id -or
        $operationalReport.data.authority.source_of_truth -or
        $operationalReport.data.authority.business_mutation_authorized -or
        $operationalReport.data.authority.external_effect_created) {
        throw "The governed operational report failed reconciliation or authority checks"
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
    if ($metrics.Content -notmatch 'uok_next_durable_work_stop') {
        throw "The authenticated metrics endpoint did not expose durable-work telemetry"
    }

    $objectStoreQualification = (& podman exec uok-next-app-a-1 /app/bin/uok_next rpc `
            "UokNext.Release.ObjectStoreQualification.run!()" | Out-String)
    if ($LASTEXITCODE -ne 0 -or
        $objectStoreQualification -notmatch
            'Object-store create-only, integrity, and deletion qualification passed') {
        throw "The immutable bounded object-store qualification failed"
    }

    $durableWorkDrained = $false
    $durableState = $null
    foreach ($attempt in 1..30) {
        $durableStateJson = (& podman compose -f $composePath exec -T postgres psql `
                -v ON_ERROR_STOP=1 `
                -U "${env:UOK_DB_USER}" `
                -d "${env:UOK_DB_NAME}" `
                -Atc "SELECT json_build_object('events', count(*), 'completed_jobs', count(*) FILTER (WHERE job.status = 'completed'), 'deliveries', count(delivery.id), 'pending', count(*) FILTER (WHERE event.status IN ('pending', 'publishing')), 'dead_letter', count(*) FILTER (WHERE event.status = 'dead_letter')) FROM kernel_outbox_events event LEFT JOIN kernel_durable_jobs job ON job.tenant_id = event.tenant_id AND job.outbox_event_id = event.id LEFT JOIN kernel_outbox_deliveries delivery ON delivery.tenant_id = event.tenant_id AND delivery.outbox_event_id = event.id AND delivery.consumer = 'kernel.local_handoff.v1'" |
                Out-String).Trim()
        if ($LASTEXITCODE -ne 0) {
            throw "The durable-work state could not be inspected"
        }

        $durableState = $durableStateJson | ConvertFrom-Json
        if ([int]$durableState.events -gt 0 -and
            [int]$durableState.events -eq [int]$durableState.completed_jobs -and
            [int]$durableState.events -eq [int]$durableState.deliveries -and
            [int]$durableState.pending -eq 0 -and [int]$durableState.dead_letter -eq 0) {
            $durableWorkDrained = $true
            break
        }
        Start-Sleep -Seconds 1
    }
    if (-not $durableWorkDrained) {
        throw "The PostgreSQL durable handoff did not drain every committed outbox event"
    }

    & podman compose -f $composePath stop app-a app-b
    if ($LASTEXITCODE -ne 0) {
        throw "The application replicas could not be stopped for durable-work recovery proof"
    }

    $recoveryFixture = (& podman compose -f $composePath exec -T postgres psql `
            -At `
            -U "${env:UOK_DB_USER}" `
            -d "${env:UOK_DB_NAME}" `
            -f /qualification/seed_expired_outbox_lease.sql | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "The expired durable-work lease fixture could not be established"
    }
    $recoveryMatch = [regex]::Match(
        $recoveryFixture,
        '^([0-9a-f-]{36})\|([0-9a-f-]{36})\|([1-9][0-9]*)$'
    )
    if (-not $recoveryMatch.Success) {
        throw "The expired durable-work lease receipt was malformed"
    }
    $recoveryJobId = $recoveryMatch.Groups[1].Value
    $recoveryEventId = $recoveryMatch.Groups[2].Value
    $recoveryAttemptCount = [int]$recoveryMatch.Groups[3].Value

    & podman compose -f $composePath up -d app-a
    if ($LASTEXITCODE -ne 0) {
        throw "The first application replica could not restart for durable-work recovery"
    }

    $durableWorkRecovered = $false
    foreach ($attempt in 1..30) {
        $recoveryState = (& podman compose -f $composePath exec -T postgres psql `
                -U "${env:UOK_DB_USER}" `
                -d "${env:UOK_DB_NAME}" `
                -Atc "SELECT job.status || '|' || event.status || '|' || job.attempt_count::text FROM kernel_durable_jobs job JOIN kernel_outbox_events event ON event.tenant_id = job.tenant_id AND event.id = job.outbox_event_id WHERE job.id = '$recoveryJobId'::uuid AND event.id = '$recoveryEventId'::uuid" |
                Out-String).Trim()
        if ($LASTEXITCODE -ne 0) {
            throw "The durable-work recovery state could not be inspected"
        }
        if ($recoveryState -eq "completed|published|$recoveryAttemptCount") {
            $durableWorkRecovered = $true
            break
        }
        Start-Sleep -Seconds 1
    }
    if (-not $durableWorkRecovered) {
        throw "The restarted worker did not reconcile the expired receipt-present lease"
    }

    $recoveredReplicaReady = $false
    foreach ($attempt in 1..30) {
        if (Test-NativeCommand -FilePath "podman" -Arguments @(
                "exec", "uok-next-app-a-1", "wget", "-qO-",
                "http://127.0.0.1:4000/api/v1/health/ready"
            )) {
            $recoveredReplicaReady = $true
            break
        }
        Start-Sleep -Seconds 1
    }
    if (-not $recoveredReplicaReady) {
        throw "The recovered application replica did not become ready"
    }

    $recoveryMetrics = (& podman exec uok-next-app-a-1 wget -qO- `
            --header="Authorization: Bearer $($env:UOK_LOCAL_METRICS_TOKEN)" `
            http://127.0.0.1:4000/api/v1/metrics | Out-String)
    if ($LASTEXITCODE -ne 0 -or
        $recoveryMetrics -notmatch 'uok_next_durable_work_recovery_count') {
        throw "The recovered worker did not expose bounded recovery telemetry"
    }

    & podman compose -f $composePath up -d app-b
    if ($LASTEXITCODE -ne 0) {
        throw "The second application replica could not restart after recovery proof"
    }

    $secondReplicaReady = $false
    foreach ($attempt in 1..30) {
        if (Test-NativeCommand -FilePath "podman" -Arguments @(
                "exec", "uok-next-app-b-1", "wget", "-qO-",
                "http://127.0.0.1:4000/api/v1/health/ready"
            )) {
            $secondReplicaReady = $true
            break
        }
        Start-Sleep -Seconds 1
    }
    if (-not $secondReplicaReady) {
        throw "The second application replica did not become ready after recovery proof"
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
            $failoverReport = Invoke-RestMethod -Uri $operationalReportUri `
                -Headers $readHeaders -TimeoutSec 5 -DisableKeepAlive

            if ($failoverReady.status -ne "ready" -or $failoverRelease.revision -ne $revision -or
                $failoverReport.data.projection_id -ne $operationalReport.data.projection_id) {
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
        browser_shell = "HTTP 200 through the isolated local qualification proxy"
        party_onboarding_tenant_id = $env:UOK_LOCAL_TENANT_ID
        party_onboarding_flow = "authenticated create, evidence, replay, task, approval, and final read passed"
        party_onboarding_qualified_party_id = $party.data.id
        product_sourcing_flow = "product, two locations, approved supplier, lane, evidence replay, exact task, approval, and final read passed"
        product_sourcing_qualified_product_id = $product.data.id
        product_sourcing_qualified_lane_id = $lane.data.id
        procurement_comparison_flow = "requisition, RFQ, two attributable quotes, verified evidence, deterministic ranking, exact task, and approval passed"
        procurement_qualified_rfq_id = $rfq.data.id
        procurement_qualified_comparison_id = $comparison.data.id
        purchase_commitment_proposal_flow = "source-derived terms, verified evidence, exact task, approval, final read, and no downstream or external effect passed"
        purchase_commitment_qualified_proposal_id = $proposal.data.id
        shipment_readiness_flow = "source-derived proposal, server checklist, verified evidence, exact task, GO, final read, and five false effect boundaries passed"
        shipment_readiness_qualified_case_id = $readiness.data.id
        operational_reporting_flow = "live repeatable-read projection, six governed stages, five verified evidence references, bounded audit and delivery lineage, deterministic reconciliation, zero-stale failure policy, and three false authority boundaries passed"
        operational_reporting_projection_id = $operationalReport.data.projection_id
        durable_work = "$($durableState.events) committed events reached idempotent local handoff; retry/dead-letter tests passed; expired receipt-present lease recovered after restart without another attempt"
        durable_work_recovery_job_id = $recoveryJobId
        local_identity_credential_path = $identityCredentialPath
        replicas = 2
        single_replica_failover = "4 readiness, release, and operational-report probes passed"
    } | ConvertTo-Json
}
finally {
    Pop-Location
}
