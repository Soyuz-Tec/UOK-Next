[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$packagePath = Join-Path $repoRoot "web/package.json"
$lockPath = Join-Path $repoRoot "web/package-lock.json"
$toolchainPath = Join-Path $repoRoot "config/toolchain.json"

$package = Get-Content -LiteralPath $packagePath -Raw | ConvertFrom-Json
$lockText = Get-Content -LiteralPath $lockPath -Raw
$toolchain = Get-Content -LiteralPath $toolchainPath -Raw | ConvertFrom-Json

$expectedVersions = @{
    "react" = [string]$toolchain.frontend.react
    "react-dom" = [string]$toolchain.frontend.react_dom
    "vite" = [string]$toolchain.frontend.vite
    "@typescript/native" = "npm:typescript@$($toolchain.frontend.typescript_native)"
    "typescript" = "npm:@typescript/typescript6@$($toolchain.frontend.typescript_compatibility_api)"
}

foreach ($dependency in $expectedVersions.GetEnumerator()) {
    $actual = if ($package.dependencies.PSObject.Properties.Name -contains $dependency.Key) {
        [string]$package.dependencies.($dependency.Key)
    }
    else {
        [string]$package.devDependencies.($dependency.Key)
    }

    if ($actual -cne $dependency.Value) {
        throw "Frontend dependency '$($dependency.Key)' must be exactly '$($dependency.Value)', found '$actual'"
    }
}

if ($package.engines.node -cne $toolchain.frontend.node) {
    throw "package.json Node engine must match config/toolchain.json"
}

if ($package.packageManager -cne "npm@$($toolchain.frontend.npm)") {
    throw "package.json packageManager must pin the governed npm version"
}

if ($lockText -notmatch '"lockfileVersion"\s*:\s*3' -or
    $lockText -notmatch '"name"\s*:\s*"@uok-next/web"') {
    throw "The npm v11 lockfile is missing or does not belong to the governed web workspace"
}

foreach ($requiredScript in @("format:check", "lint", "typecheck", "typecheck:compat", "test", "build", "quality")) {
    if ([string]::IsNullOrWhiteSpace($package.scripts.$requiredScript)) {
        throw "Frontend quality script '$requiredScript' is required"
    }
}

$containerText = Get-Content -LiteralPath (Join-Path $repoRoot "Containerfile") -Raw
if ($containerText -notmatch [regex]::Escape($toolchain.frontend.node_image) -or
    $containerText -notmatch 'npm ci --ignore-scripts --no-audit --no-fund' -or
    $containerText -notmatch 'COPY --from=web_build /build/uok-ui priv/static/uok-ui') {
    throw "Containerfile must build the locked web workspace in the digest-pinned Node image"
}

$deliveryFiles = @(
    Join-Path $repoRoot "web/index.html"
    Join-Path $repoRoot "web/src"
)
$externalReferences = @(
    Get-ChildItem -LiteralPath $deliveryFiles -File -Recurse |
        Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match 'https?://|(?:src|href)\s*=\s*["'']//|url\(\s*["'']?//' } |
        ForEach-Object FullName
)

if ($externalReferences.Count -gt 0) {
    throw "Initial shell must not load runtime assets from external origins: $($externalReferences -join ', ')"
}

Write-Output "Web foundation verification passed."
Write-Output "Pinned Node $($toolchain.frontend.node), npm $($toolchain.frontend.npm), React $($toolchain.frontend.react), Vite $($toolchain.frontend.vite), and TypeScript $($toolchain.frontend.typescript_native)."
