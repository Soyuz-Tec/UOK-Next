[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$toolchainPath = Join-Path $repoRoot "config/toolchain.json"
$toolchain = Get-Content -LiteralPath $toolchainPath -Raw | ConvertFrom-Json
$integrityModule = Join-Path $repoRoot "scripts\security\ArtifactIntegrity.psm1"
Import-Module -Name $integrityModule -Force

function Invoke-VerifiedFrameworkDownload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ArtifactName,
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$DestinationPath,
        [Parameter(Mandatory = $true)][long]$ExpectedBytes,
        [Parameter(Mandatory = $true)][string]$ExpectedSha512,
        [Parameter(Mandatory = $true)][string]$CurlPath
    )

    & $CurlPath --proto '=https' --tlsv1.2 --max-filesize $ExpectedBytes `
        --remove-on-error --connect-timeout 30 --max-time 300 -fsS -o $DestinationPath $Uri
    if ($LASTEXITCODE -ne 0) {
        throw "$ArtifactName download failed with exit code $LASTEXITCODE"
    }
    if ((Get-Item -LiteralPath $DestinationPath).Length -ne $ExpectedBytes) {
        throw "$ArtifactName download size does not match the repository pin"
    }
    Assert-FileSha512 -Path $DestinationPath -ExpectedSha512 $ExpectedSha512
}

$elixirVersion = [string]$toolchain.primary.elixir
$otpVersion = [string]$toolchain.primary.erlang_otp
$otpMajor = $otpVersion.Split('.')[0]
$phoenixVersion = [string]$toolchain.primary.phoenix_new
$hexVersion = [string]$toolchain.primary.hex
$rebar3Version = [string]$toolchain.primary.rebar3
$hexArchiveUrl = [string]$toolchain.bootstrap.hex_archive_url
$hexArchiveSha512 = [string]$toolchain.bootstrap.hex_archive_sha512
$hexArchiveSize = [long]$toolchain.bootstrap.hex_archive_size_bytes
$rebar3Url = [string]$toolchain.bootstrap.rebar3_url
$rebar3Sha512 = [string]$toolchain.bootstrap.rebar3_sha512
$rebar3Size = [long]$toolchain.bootstrap.rebar3_size_bytes
$phoenixPackageUrl = [string]$toolchain.bootstrap.phx_new_package_url
$phoenixPackageSha512 = [string]$toolchain.bootstrap.phx_new_package_sha512
$phoenixPackageSize = [long]$toolchain.bootstrap.phx_new_package_size_bytes
$phoenixContentsSha512 = [string]$toolchain.bootstrap.phx_new_contents_sha512
$otpArchiveSha256 = [string]$toolchain.bootstrap.otp_archive_sha256
$elixirArchiveSha256 = [string]$toolchain.bootstrap.elixir_archive_sha256
$hexMixSha512 = $hexArchiveSha512.ToLowerInvariant()
$rebar3MixSha512 = $rebar3Sha512.ToLowerInvariant()
if ($otpArchiveSha256 -cnotmatch '^[0-9A-F]{64}$' -or
    $elixirArchiveSha256 -cnotmatch '^[0-9A-F]{64}$') {
    throw "OTP and Elixir archive SHA-256 pins must contain 64 uppercase hexadecimal characters"
}
$otpIdentity = $otpArchiveSha256.ToLowerInvariant()
$elixirIdentity = $elixirArchiveSha256.ToLowerInvariant()
$installRoot = Join-Path $env:USERPROFILE ".elixir-install\installs"
$otpInstall = Join-Path $installRoot "otp\$otpVersion-$otpIdentity"
$elixirInstall = Join-Path $installRoot "elixir\$elixirVersion-otp-$otpMajor-$elixirIdentity"
$otpBin = Join-Path $otpInstall "bin"
$elixirBin = Join-Path $elixirInstall "bin"
$mixPath = Join-Path $elixirBin "mix.bat"
$escriptPath = Join-Path $otpBin "escript.exe"
$curlPath = Join-Path $env:SystemRoot "System32\curl.exe"

if (-not (Test-Path -LiteralPath $mixPath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $escriptPath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $curlPath -PathType Leaf)) {
    throw "Content-addressed language tools and Windows system curl.exe must exist before framework setup"
}
Assert-VerifiedInstallDirectory -Root $otpInstall -SourceSha256 $otpArchiveSha256 `
    -ExpectedRelativePaths @("bin\erl.exe", "bin\escript.exe")
Assert-VerifiedInstallDirectory -Root $elixirInstall -SourceSha256 $elixirArchiveSha256 `
    -ExpectedRelativePaths @("bin\elixir.bat", "bin\mix.bat")

$env:PATH = "$otpBin;$elixirBin;$env:PATH"

Assert-HttpsUri -Uri $hexArchiveUrl
Assert-HttpsUri -Uri $rebar3Url
Assert-HttpsUri -Uri $phoenixPackageUrl
if (-not $hexArchiveUrl.EndsWith("/hex-$hexVersion-otp-$otpMajor.ez", [System.StringComparison]::Ordinal) -or
    -not $rebar3Url.EndsWith("/rebar3-$rebar3Version-otp-$otpMajor", [System.StringComparison]::Ordinal) -or
    -not $phoenixPackageUrl.EndsWith("/phx_new-$phoenixVersion.tar", [System.StringComparison]::Ordinal)) {
    throw "Framework artifact URLs must match the pinned Hex, Rebar3, Phoenix, and OTP versions"
}
if ($hexArchiveSize -le 0 -or $rebar3Size -le 0 -or $phoenixPackageSize -le 0 -or
    $phoenixContentsSha512 -cnotmatch '^[0-9A-F]{128}$') {
    throw "Framework artifact size and inner Phoenix digest pins must be valid"
}
$tempRoot = [System.IO.Path]::GetTempPath()
$taskTempRoot = Join-Path $tempRoot ("uok-next-framework-" + [guid]::NewGuid().ToString("N"))
$null = New-Item -ItemType Directory -Path $taskTempRoot
$hexArchivePath = Join-Path $taskTempRoot "hex-$hexVersion.ez"
$rebar3Path = Join-Path $taskTempRoot "rebar3"
$phoenixPackagePath = Join-Path $taskTempRoot "phx_new-$phoenixVersion.tar"
$phoenixOuterPath = Join-Path $taskTempRoot "package"
$phoenixSourcePath = Join-Path $taskTempRoot "source"
$phoenixArchivePath = Join-Path $taskTempRoot "phx_new-$phoenixVersion.ez"
$previousMixEnv = $env:MIX_ENV

try {
    Invoke-VerifiedFrameworkDownload -ArtifactName "Hex" -Uri $hexArchiveUrl `
        -DestinationPath $hexArchivePath -ExpectedBytes $hexArchiveSize `
        -ExpectedSha512 $hexArchiveSha512 -CurlPath $curlPath

    & $mixPath archive.install $hexArchivePath --sha512 $hexMixSha512 --force
    if ($LASTEXITCODE -ne 0) {
        throw "Hex installation failed with exit code $LASTEXITCODE"
    }
    $hexInfo = (& $mixPath hex.info | Out-String)
    if ($LASTEXITCODE -ne 0 -or $hexInfo -notmatch "(?m)^Hex:\s+$([regex]::Escape($hexVersion))\r?$") {
        throw "Installed Hex version does not match the repository pin"
    }

    Invoke-VerifiedFrameworkDownload -ArtifactName "Rebar3" -Uri $rebar3Url `
        -DestinationPath $rebar3Path -ExpectedBytes $rebar3Size `
        -ExpectedSha512 $rebar3Sha512 -CurlPath $curlPath
    $rebar3Info = (& $escriptPath $rebar3Path version | Out-String)
    if ($LASTEXITCODE -ne 0 -or
        $rebar3Info -notmatch "^rebar\s+$([regex]::Escape($rebar3Version))\s+on\s+") {
        throw "Downloaded Rebar3 version does not match the repository pin"
    }

    & $mixPath local.rebar rebar3 $rebar3Path --sha512 $rebar3MixSha512 --force
    if ($LASTEXITCODE -ne 0) {
        throw "Rebar3 installation failed with exit code $LASTEXITCODE"
    }

    Invoke-VerifiedFrameworkDownload -ArtifactName "Phoenix package" -Uri $phoenixPackageUrl `
        -DestinationPath $phoenixPackagePath -ExpectedBytes $phoenixPackageSize `
        -ExpectedSha512 $phoenixPackageSha512 -CurlPath $curlPath

    Expand-SafeTarArchive -ArchivePath $phoenixPackagePath -DestinationPath $phoenixOuterPath
    $phoenixContentsPath = Join-Path $phoenixOuterPath "contents.tar.gz"
    Assert-FileSha512 -Path $phoenixContentsPath -ExpectedSha512 $phoenixContentsSha512
    Expand-SafeTarArchive -ArchivePath $phoenixContentsPath `
        -DestinationPath $phoenixSourcePath -Gzip

    $env:MIX_ENV = "prod"
    Push-Location $phoenixSourcePath
    try {
        & $mixPath archive.build -o $phoenixArchivePath
        if ($LASTEXITCODE -ne 0) {
            throw "Phoenix archive build failed with exit code $LASTEXITCODE"
        }
    }
    finally {
        Pop-Location
    }

    $phoenixArchiveSha512 = (Get-FileHash -LiteralPath $phoenixArchivePath -Algorithm SHA512).Hash.ToLowerInvariant()
    & $mixPath archive.install $phoenixArchivePath --sha512 $phoenixArchiveSha512 --force
    if ($LASTEXITCODE -ne 0) {
        throw "Phoenix generator installation failed with exit code $LASTEXITCODE"
    }

    & $mixPath phx.new --version
    if ($LASTEXITCODE -ne 0) {
        throw "Phoenix generator verification failed with exit code $LASTEXITCODE"
    }
}
finally {
    if ($null -eq $previousMixEnv) {
        Remove-Item -LiteralPath Env:MIX_ENV -ErrorAction SilentlyContinue
    }
    else {
        $env:MIX_ENV = $previousMixEnv
    }

    $resolvedTempRoot = [System.IO.Path]::GetFullPath($tempRoot)
    $resolvedTaskTempRoot = [System.IO.Path]::GetFullPath($taskTempRoot)
    if (-not $resolvedTaskTempRoot.StartsWith($resolvedTempRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
        $resolvedTaskTempRoot -ceq $resolvedTempRoot) {
        throw "Refusing to remove an unverified framework temporary directory"
    }
    Remove-Item -LiteralPath $resolvedTaskTempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
