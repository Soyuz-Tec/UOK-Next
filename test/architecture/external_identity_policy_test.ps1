[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$verifierPath = Join-Path $repoRoot "scripts/verify_external_identity_policy.ps1"
$systemTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$testRoot = [IO.Path]::GetFullPath(
    (Join-Path $systemTemp ("uok-next-identity-policy-" + [Guid]::NewGuid().ToString("N")))
)

if (-not $testRoot.StartsWith($systemTemp, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to create identity-policy fixtures outside the system temporary directory"
}

function New-ValidPolicy {
    [ordered]@{
        schema_version = 1
        mode = "role_based"
        external_roles = @(
            [ordered]@{
                id = "communications_system"
                display_name = "External communications system"
            }
        )
        allowed_catalog_fields = @("id", "display_name", "identity_class", "status", "record_types")
        exact_identity_contexts = @(
            "dependency_manifest_or_lock",
            "build_or_runtime_provenance",
            "license_or_attribution",
            "security_advisory_or_vulnerability_evidence",
            "interoperability_configuration",
            "operator_runbook",
            "implementation_selection_adr"
        )
    }
}

function New-ValidCatalog {
    [ordered]@{
        schema_version = 1
        external_systems = @(
            [ordered]@{
                id = "communications_system"
                display_name = "External communications system"
                identity_class = "role_based"
                status = "existing"
                record_types = @("conversation")
            }
        )
    }
}

function Write-JsonFixture {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Value,
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $Value | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Assert-VerifierFailure {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ExpectedMessage,
        [Parameter(Mandatory = $true)]
        [scriptblock]$Action
    )

    try {
        $null = & $Action
    }
    catch {
        if ($_.Exception.Message -notlike "*$ExpectedMessage*") {
            throw "Expected failure containing '$ExpectedMessage' but received: $($_.Exception.Message)"
        }
        return
    }

    throw "Expected identity-policy verification to fail with '$ExpectedMessage'"
}

New-Item -ItemType Directory -Path $testRoot | Out-Null
$catalogPath = Join-Path $testRoot "module_catalog.json"
$policyPath = Join-Path $testRoot "external_identity_policy.json"

try {
    Write-JsonFixture -Value (New-ValidCatalog) -Path $catalogPath
    Write-JsonFixture -Value (New-ValidPolicy) -Path $policyPath
    $null = & $verifierPath -CatalogPath $catalogPath -PolicyPath $policyPath

    $identifyingCatalog = New-ValidCatalog
    $identifyingCatalog.external_systems[0].provider_name = "not_permitted"
    Write-JsonFixture -Value $identifyingCatalog -Path $catalogPath
    Assert-VerifierFailure -ExpectedMessage "fields must exactly match" -Action {
        & $verifierPath -CatalogPath $catalogPath -PolicyPath $policyPath
    }

    $weakenedPolicy = New-ValidPolicy
    $weakenedPolicy.allowed_catalog_fields += "implementation_name"
    Write-JsonFixture -Value (New-ValidCatalog) -Path $catalogPath
    Write-JsonFixture -Value $weakenedPolicy -Path $policyPath
    Assert-VerifierFailure -ExpectedMessage "must exactly match the governed schema" -Action {
        & $verifierPath -CatalogPath $catalogPath -PolicyPath $policyPath
    }

    Write-JsonFixture -Value (New-ValidPolicy) -Path $policyPath

    $expandedExceptionPolicy = New-ValidPolicy
    $expandedExceptionPolicy.exact_identity_contexts += "general_product_material"
    Write-JsonFixture -Value $expandedExceptionPolicy -Path $policyPath
    Assert-VerifierFailure -ExpectedMessage "must exactly match the governed exceptions" -Action {
        & $verifierPath -CatalogPath $catalogPath -PolicyPath $policyPath
    }

    Write-JsonFixture -Value (New-ValidPolicy) -Path $policyPath

    $unknownRoleCatalog = New-ValidCatalog
    $unknownRoleCatalog.external_systems[0].id = "unknown_external_system"
    Write-JsonFixture -Value $unknownRoleCatalog -Path $catalogPath
    Assert-VerifierFailure -ExpectedMessage "not an approved role-based identity" -Action {
        & $verifierPath -CatalogPath $catalogPath -PolicyPath $policyPath
    }

    $mismatchedLabelCatalog = New-ValidCatalog
    $mismatchedLabelCatalog.external_systems[0].display_name = "Implementation-specific label"
    Write-JsonFixture -Value $mismatchedLabelCatalog -Path $catalogPath
    Assert-VerifierFailure -ExpectedMessage "display name does not match" -Action {
        & $verifierPath -CatalogPath $catalogPath -PolicyPath $policyPath
    }
}
finally {
    $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
    if (-not $resolvedTestRoot.StartsWith($systemTemp, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove identity-policy fixtures outside the system temporary directory"
    }
    Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
}

Write-Output "External identity policy negative tests passed."
