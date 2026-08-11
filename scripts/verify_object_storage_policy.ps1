[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$policyPath = Join-Path $repoRoot "config/object_store_policy.json"
$policy = Get-Content -LiteralPath $policyPath -Raw | ConvertFrom-Json

if ($policy.schema_version -ne 1 -or $policy.protocol -cne "S3") {
    throw "Unsupported object-storage policy contract"
}

$image = [string]$policy.local_qualifier.image
if ($image -cnotmatch '^docker\.io/chrislusf/seaweedfs@sha256:[0-9a-f]{64}$') {
    throw "Local object storage must use the approved digest-pinned SeaweedFS image"
}
if ($policy.local_qualifier.version -cne "4.37" -or
    $policy.local_qualifier.license -cne "Apache-2.0" -or
    $policy.local_qualifier.container_user -cne "10001:10001") {
    throw "Local object-store identity, license, or runtime user drifted"
}
if ($policy.contract.maximum_object_bytes -ne 8388608 -or
    $policy.contract.maximum_control_response_bytes -ne 65536 -or
    $policy.contract.initial_state -cne "quarantined" -or
    $policy.contract.digest -cne "SHA-256" -or
    $policy.contract.key_source -cne "server-derived" -or
    $policy.contract.metadata_authority -cne "PostgreSQL" -or
    $policy.contract.browser_direct_access -ne $false -or
    $policy.contract.production_provider_selected -ne $false) {
    throw "The bounded evidence-object authority contract drifted"
}

$composeText = Get-Content -LiteralPath (Join-Path $repoRoot "compose.yaml") -Raw
$requiredComposePatterns = @(
    [regex]::Escape($image),
    '127\.0\.0\.1:\$\{UOK_OBJECT_STORE_PORT:-18333\}:8333',
    'user:\s*"10001:10001"',
    'read_only:\s*true',
    'no-new-privileges:true',
    'cap_drop:\s*\r?\n\s*- ALL',
    'OBJECT_STORE_URL:\s*http://object-store:8333',
    'OBJECT_STORE_MAX_OBJECT_BYTES:\s*8388608',
    'find /data -mindepth 1',
    'cap_add:\s*\r?\n\s*- CHOWN\s*\r?\n\s*- DAC_OVERRIDE\s*\r?\n\s*- FOWNER',
    '-s3\.allowDeleteBucketNotEmpty=false',
    '-volume\.allowUntrustedRemoteEndpoints=false'
)
foreach ($pattern in $requiredComposePatterns) {
    if ($composeText -notmatch $pattern) {
        throw "compose.yaml is missing required object-store control '$pattern'"
    }
}
if ($composeText -match '(?i)minio|minio/minio|rustfs') {
    throw "Unapproved object-store providers must not enter the Gate 1 runtime"
}

$runtimeText = Get-Content -LiteralPath (Join-Path $repoRoot "config/runtime.exs") -Raw
foreach ($pattern in @(
    'OBJECT_STORE_URL',
    'expected_scheme = if local_qualification\?, do: "http", else: "https"',
    'uri\.host == "object-store"',
    'OBJECT_STORE_ACCESS_KEY',
    'OBJECT_STORE_SECRET_KEY',
    'OBJECT_STORE_MAX_OBJECT_BYTES',
    'parse_bounded_integer\.\("OBJECT_STORE_MAX_OBJECT_BYTES", "8388608", 1, 8_388_608\)'
)) {
    if ($runtimeText -notmatch $pattern) {
        throw "Runtime object-store validation is missing '$pattern'"
    }
}

$domainText = Get-Content -LiteralPath (
    Join-Path $repoRoot "lib/uok_next/modules/platform/evidence/domain/evidence_object.ex"
) -Raw
$adapterText = Get-Content -LiteralPath (
    Join-Path $repoRoot "lib/uok_next/modules/platform/evidence/infrastructure/s3_object_store.ex"
) -Raw
$clientText = Get-Content -LiteralPath (
    Join-Path $repoRoot "lib/uok_next/modules/platform/evidence/infrastructure/bounded_req_http_client.ex"
) -Raw
$configText = Get-Content -LiteralPath (Join-Path $repoRoot "config/config.exs") -Raw
if ($domainText -notmatch ':crypto\.hash\(:sha256' -or
    $domainText -notmatch 'tenants/#\{tenant_id\}/evidence/#\{evidence_id\}/sha256/#\{digest\}' -or
    $domainText -notmatch 'maximum_bytes in 1\.\.8_388_608' -or
    $adapterText -notmatch 'if_none_match:\s*"\*"' -or
    $adapterText -notmatch 'S3\.head_object' -or
    $adapterText -notmatch 'S3\.presigned_url' -or
    $adapterText -notmatch 'redirect:\s*false' -or
    $adapterText -notmatch 'bounded_collector' -or
    $adapterText -notmatch 'EvidenceObject\.verify_content') {
    throw "The S3 adapter must preserve immutable, content-addressed, read-verified objects"
}
if ($configText -notmatch 'http_client:\s*UokNext\.Modules\.Platform\.Evidence\.Infrastructure\.BoundedReqHttpClient' -or
    $clientText -notmatch '@maximum_response_bytes 65_536' -or
    $clientText -notmatch 'Keyword\.put\(:into, bounded_collector\(\)\)' -or
    $clientText -notmatch ':response_too_large') {
    throw "S3 control-operation responses must fail closed at the bounded HTTP client"
}

$catalog = Get-Content -LiteralPath (Join-Path $repoRoot "config/module_catalog.json") -Raw |
    ConvertFrom-Json
$evidenceModule = @($catalog.modules | Where-Object id -eq "platform.evidence")
if ($evidenceModule.Count -ne 1 -or $evidenceModule[0].status -ne "in_progress") {
    throw "platform.evidence must own the in-progress evidence-object contract"
}

$webMatches = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot "web/src") -File -Recurse |
    Select-String -Pattern 'OBJECT_STORE_(ACCESS_KEY|SECRET_KEY)|AWS_SECRET_ACCESS_KEY')
if ($webMatches.Count -gt 0) {
    throw "Object-store credentials must never enter browser source"
}

Write-Output "Object-storage policy verification passed for SeaweedFS $($policy.local_qualifier.version)."
Write-Output "Validated S3 isolation, non-root runtime, server-derived keys, SHA-256 integrity, and PostgreSQL metadata authority."
