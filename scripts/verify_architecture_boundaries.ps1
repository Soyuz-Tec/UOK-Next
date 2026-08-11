[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

function Get-SourceText {
    param([Parameter(Mandatory = $true)][string[]]$Paths)

    foreach ($relativePath in $Paths) {
        $path = Join-Path $repoRoot $relativePath
        if (-not (Test-Path -LiteralPath $path)) {
            continue
        }

        Get-ChildItem -LiteralPath $path -File -Recurse -Filter "*.ex" | ForEach-Object {
            [pscustomobject]@{
                Path = $_.FullName.Substring($repoRoot.Length + 1).Replace('\', '/')
                Text = Get-Content -LiteralPath $_.FullName -Raw
            }
        }
    }
}

function Get-LayerSourceText {
    param([Parameter(Mandatory = $true)][string[]]$LayerNames)

    $moduleRoot = Join-Path $repoRoot "lib/uok_next/modules"
    if (-not (Test-Path -LiteralPath $moduleRoot -PathType Container)) {
        return
    }

    Get-ChildItem -LiteralPath $moduleRoot -Directory -Recurse |
        Where-Object { $LayerNames -contains $_.Name } |
        ForEach-Object {
            Get-ChildItem -LiteralPath $_.FullName -File -Recurse -Filter "*.ex" | ForEach-Object {
                [pscustomobject]@{
                    Path = $_.FullName.Substring($repoRoot.Length + 1).Replace('\', '/')
                    Text = Get-Content -LiteralPath $_.FullName -Raw
                }
            }
        }
}

function Assert-NoDependency {
    param(
        [Parameter(Mandatory = $true)][object[]]$Sources,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][string]$Rule
    )

    $violations = @($Sources | Where-Object { $_.Text -match $Pattern } | ForEach-Object Path)
    if ($violations.Count -gt 0) {
        throw "$Rule Violations: $($violations -join ', ')"
    }
}

$kernel = @(Get-SourceText -Paths @("lib/uok_next/kernel"))
$domainAndPolicies = @(Get-LayerSourceText -LayerNames @("domain", "policies"))
$application = @(Get-LayerSourceText -LayerNames @("application"))
$httpBoundary = @(Get-SourceText -Paths @(
    "lib/uok_next_web/controllers",
    "spikes/uok_next_web"
))
$nonInfrastructureModules = @($domainAndPolicies + $application)

Assert-NoDependency -Sources $kernel `
    -Pattern 'UokNext\.(Modules|Web)\.' `
    -Rule "The kernel must not depend on business modules or the HTTP boundary."

Assert-NoDependency -Sources $domainAndPolicies `
    -Pattern '(Ecto\.|Phoenix\.|Plug\.|Ash\.|UokNext\.Repo|\.Infrastructure\.)' `
    -Rule "Domain and policy code must remain framework and persistence independent."

Assert-NoDependency -Sources $application `
    -Pattern '(Phoenix\.|Plug\.|Ash\.|UokNext\.Repo|\.Infrastructure\.)' `
    -Rule "Application services must use ports rather than HTTP or persistence implementations."

Assert-NoDependency -Sources $httpBoundary `
    -Pattern '(UokNext\.Repo|\.Application\.|\.Domain\.|\.Infrastructure\.|\.Policies\.)' `
    -Rule "HTTP code must call module Public contracts instead of private layers."

Assert-NoDependency -Sources $nonInfrastructureModules `
    -Pattern 'alias\s+UokNext\.Repo' `
    -Rule "Only infrastructure and kernel transaction code may access the repository."

Write-Output "Architecture-boundary verification passed for $($kernel.Count + $domainAndPolicies.Count + $application.Count + $httpBoundary.Count) source files."
