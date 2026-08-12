[CmdletBinding()]
param(
    [string]$CatalogPath,
    [string]$PolicyPath
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($CatalogPath)) {
    $CatalogPath = Join-Path $repoRoot "config/module_catalog.json"
}

if ([string]::IsNullOrWhiteSpace($PolicyPath)) {
    $PolicyPath = Join-Path $repoRoot "config/external_identity_policy.json"
}

foreach ($requiredPath in @($CatalogPath, $PolicyPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "External identity input does not exist as a file: $requiredPath"
    }
}

try {
    $catalog = Get-Content -LiteralPath $CatalogPath -Raw | ConvertFrom-Json
    $policy = Get-Content -LiteralPath $PolicyPath -Raw | ConvertFrom-Json
}
catch {
    throw "External identity policy inputs must be valid JSON: $($_.Exception.Message)"
}

if ($catalog.schema_version -ne 1) {
    throw "External identity verifier requires module catalog schema version 1"
}

if ($policy.schema_version -ne 1 -or $policy.mode -ne "role_based") {
    throw "External identity policy must use supported schema version 1 and role_based mode"
}

if (@($policy.external_roles).Count -eq 0) {
    throw "External identity policy must declare at least one role"
}

$requiredExactIdentityContexts = @(
    "dependency_manifest_or_lock",
    "build_or_runtime_provenance",
    "license_or_attribution",
    "security_advisory_or_vulnerability_evidence",
    "interoperability_configuration",
    "operator_runbook",
    "implementation_selection_adr"
)
$exactIdentityContexts = @($policy.exact_identity_contexts)
$unexpectedIdentityContexts = @(
    $exactIdentityContexts |
        Where-Object { $requiredExactIdentityContexts -cnotcontains $_ }
)
$missingIdentityContexts = @(
    $requiredExactIdentityContexts |
        Where-Object { $exactIdentityContexts -cnotcontains $_ }
)
if ($unexpectedIdentityContexts.Count -gt 0 -or $missingIdentityContexts.Count -gt 0) {
    throw "External identity policy contexts must exactly match the governed exceptions"
}

$approvedRoles = @{}
$approvedDisplayNames = @{}
foreach ($externalRole in @($policy.external_roles)) {
    if ($externalRole.id -cnotmatch '^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$') {
        throw "External role id '$($externalRole.id)' is not a stable snake_case identifier"
    }
    if ([string]::IsNullOrWhiteSpace($externalRole.display_name)) {
        throw "External role '$($externalRole.id)' requires a display name"
    }
    if ($approvedRoles.ContainsKey($externalRole.id)) {
        throw "External identity policy repeats role '$($externalRole.id)'"
    }
    if ($approvedDisplayNames.ContainsKey($externalRole.display_name)) {
        throw "External identity policy repeats display name '$($externalRole.display_name)'"
    }

    $approvedRoles[$externalRole.id] = $externalRole.display_name
    $approvedDisplayNames[$externalRole.display_name] = $externalRole.id
}

$requiredCatalogFields = @("id", "display_name", "identity_class", "status", "record_types")
$allowedCatalogFields = @($policy.allowed_catalog_fields)
$unexpectedAllowedFields = @(
    $allowedCatalogFields |
        Where-Object { $requiredCatalogFields -cnotcontains $_ }
)
$missingAllowedFields = @(
    $requiredCatalogFields |
        Where-Object { $allowedCatalogFields -cnotcontains $_ }
)
if ($unexpectedAllowedFields.Count -gt 0 -or $missingAllowedFields.Count -gt 0) {
    throw "External identity policy catalog fields must exactly match the governed schema"
}

$catalogRoleIds = @{}
foreach ($externalSystem in @($catalog.external_systems)) {
    if (-not $approvedRoles.ContainsKey($externalSystem.id)) {
        throw "External system '$($externalSystem.id)' is not an approved role-based identity"
    }
    if ($catalogRoleIds.ContainsKey($externalSystem.id)) {
        throw "Module catalog repeats external role '$($externalSystem.id)'"
    }
    if ($externalSystem.identity_class -ne "role_based") {
        throw "External system '$($externalSystem.id)' must declare identity_class 'role_based'"
    }
    if ($externalSystem.display_name -cne $approvedRoles[$externalSystem.id]) {
        throw "External system '$($externalSystem.id)' display name does not match the identity policy"
    }

    $catalogFields = @($externalSystem.PSObject.Properties.Name)
    $unapprovedFields = @(
        $catalogFields |
            Where-Object { $requiredCatalogFields -cnotcontains $_ }
    )
    $missingFields = @(
        $requiredCatalogFields |
            Where-Object { $catalogFields -cnotcontains $_ }
    )
    if ($unapprovedFields.Count -gt 0 -or $missingFields.Count -gt 0) {
        throw "External system '$($externalSystem.id)' fields must exactly match the governed role schema"
    }

    $catalogRoleIds[$externalSystem.id] = $true
}

$missingRoles = @(
    $approvedRoles.Keys |
        Where-Object { -not $catalogRoleIds.ContainsKey($_) }
)
if ($missingRoles.Count -gt 0) {
    throw "Approved external roles missing from the module catalog: $($missingRoles -join ', ')"
}

Write-Output "External identity policy verification passed for $($catalogRoleIds.Count) role-based systems."
