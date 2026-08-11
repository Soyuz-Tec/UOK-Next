[CmdletBinding()]
param(
    [switch]$PersistUserPath
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$toolchainPath = Join-Path $repoRoot "config/toolchain.json"
$toolchain = Get-Content -LiteralPath $toolchainPath -Raw | ConvertFrom-Json
$integrityModule = Join-Path $PSScriptRoot "security\ArtifactIntegrity.psm1"
Import-Module -Name $integrityModule -Force
$curlPath = Join-Path $env:SystemRoot "System32\curl.exe"

if (-not (Test-Path -LiteralPath $curlPath -PathType Leaf)) {
    throw "Windows system curl.exe is required for verified toolchain downloads"
}

function Install-VerifiedZipArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ArtifactName,
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$Sha256,
        [Parameter(Mandatory = $true)][long]$ExpectedBytes,
        [Parameter(Mandatory = $true)][string]$TaskRoot,
        [Parameter(Mandatory = $true)][string]$DestinationPath,
        [Parameter(Mandatory = $true)][string[]]$ExpectedRelativePaths
    )

    if (Test-Path -LiteralPath $DestinationPath) {
        Assert-VerifiedInstallDirectory -Root $DestinationPath -SourceSha256 $Sha256 `
            -ExpectedRelativePaths $ExpectedRelativePaths
        return
    }

    Assert-HttpsUri -Uri $Uri
    $archivePath = Join-Path $TaskRoot "$ArtifactName.zip"
    $destinationParent = Split-Path -Parent $DestinationPath
    $null = [System.IO.Directory]::CreateDirectory($destinationParent)
    $stagingPath = Join-Path $destinationParent (
        ".uok-next-$ArtifactName-" + [guid]::NewGuid().ToString('N')
    )
    & $curlPath --proto '=https' --proto-redir '=https' --tlsv1.2 --location `
        --max-redirs 5 --max-filesize $ExpectedBytes --remove-on-error `
        --connect-timeout 30 --max-time 600 -fsS -o $archivePath $Uri
    if ($LASTEXITCODE -ne 0) {
        throw "$ArtifactName download failed with exit code $LASTEXITCODE"
    }
    if ((Get-Item -LiteralPath $archivePath).Length -ne $ExpectedBytes) {
        throw "$ArtifactName download size does not match the repository pin"
    }
    Assert-FileSha256 -Path $archivePath -ExpectedSha256 $Sha256
    try {
        Expand-SafeZipArchive -ArchivePath $archivePath -DestinationPath $stagingPath
        New-VerifiedInstallReceipt -Root $stagingPath -SourceSha256 $Sha256
        Assert-VerifiedInstallDirectory -Root $stagingPath -SourceSha256 $Sha256 `
            -ExpectedRelativePaths $ExpectedRelativePaths
        Move-Item -LiteralPath $stagingPath -Destination $DestinationPath
        Assert-VerifiedInstallDirectory -Root $DestinationPath -SourceSha256 $Sha256 `
            -ExpectedRelativePaths $ExpectedRelativePaths
    }
    finally {
        if (Test-Path -LiteralPath $stagingPath) {
            $resolvedParent = [System.IO.Path]::GetFullPath($destinationParent).TrimEnd(
                [System.IO.Path]::DirectorySeparatorChar
            ) + [System.IO.Path]::DirectorySeparatorChar
            $resolvedStaging = [System.IO.Path]::GetFullPath($stagingPath)
            if (-not $resolvedStaging.StartsWith($resolvedParent, [System.StringComparison]::OrdinalIgnoreCase) -or
                -not [System.IO.Path]::GetFileName($resolvedStaging).StartsWith(
                    ".uok-next-$ArtifactName-",
                    [System.StringComparison]::Ordinal
                )) {
                throw "Refusing to remove an unverified install staging directory"
            }
            Remove-Item -LiteralPath $resolvedStaging -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

$elixirVersion = [string]$toolchain.primary.elixir
$otpVersion = [string]$toolchain.primary.erlang_otp
$otpMajor = $otpVersion.Split('.')[0]
$otpArchiveUri = [string]$toolchain.bootstrap.otp_archive_url
$otpArchiveSha256 = [string]$toolchain.bootstrap.otp_archive_sha256
$otpArchiveSize = [long]$toolchain.bootstrap.otp_archive_size_bytes
$elixirArchiveUri = [string]$toolchain.bootstrap.elixir_archive_url
$elixirArchiveSha256 = [string]$toolchain.bootstrap.elixir_archive_sha256
$elixirArchiveSize = [long]$toolchain.bootstrap.elixir_archive_size_bytes

if ($otpArchiveSha256 -cnotmatch '^[0-9A-F]{64}$' -or
    $elixirArchiveSha256 -cnotmatch '^[0-9A-F]{64}$') {
    throw "OTP and Elixir archive SHA-256 pins must contain 64 uppercase hexadecimal characters"
}
if ($otpArchiveSize -le 0 -or $elixirArchiveSize -le 0) {
    throw "OTP and Elixir archive size pins must be positive"
}
$expectedOtpUri = "https://github.com/erlang/otp/releases/download/OTP-$otpVersion/otp_win64_$otpVersion.zip"
$expectedElixirUri = "https://github.com/elixir-lang/elixir/releases/download/v$elixirVersion/elixir-otp-$otpMajor.zip"
if ($otpArchiveUri -cne $expectedOtpUri -or $elixirArchiveUri -cne $expectedElixirUri) {
    throw "OTP and Elixir archive URLs must match the exact repository-pinned versions"
}

$installRoot = Join-Path $env:USERPROFILE ".elixir-install\installs"
$otpIdentity = $otpArchiveSha256.ToLowerInvariant()
$elixirIdentity = $elixirArchiveSha256.ToLowerInvariant()
$otpInstall = Join-Path $installRoot "otp\$otpVersion-$otpIdentity"
$elixirInstall = Join-Path $installRoot "elixir\$elixirVersion-otp-$otpMajor-$elixirIdentity"
$otpBin = Join-Path $otpInstall "bin"
$elixirBin = Join-Path $elixirInstall "bin"
$tempRoot = [System.IO.Path]::GetTempPath()
$taskTempRoot = Join-Path $tempRoot ("uok-next-toolchain-" + [guid]::NewGuid().ToString("N"))
$null = New-Item -ItemType Directory -Path $taskTempRoot

try {
    Install-VerifiedZipArtifact -ArtifactName "otp" -Uri $otpArchiveUri `
        -Sha256 $otpArchiveSha256 -ExpectedBytes $otpArchiveSize -TaskRoot $taskTempRoot `
        -DestinationPath $otpInstall `
        -ExpectedRelativePaths @("bin\erl.exe", "bin\escript.exe")
    Install-VerifiedZipArtifact -ArtifactName "elixir" -Uri $elixirArchiveUri `
        -Sha256 $elixirArchiveSha256 -ExpectedBytes $elixirArchiveSize -TaskRoot $taskTempRoot `
        -DestinationPath $elixirInstall `
        -ExpectedRelativePaths @("bin\elixir.bat", "bin\mix.bat")
}
finally {
    $resolvedTempRoot = [System.IO.Path]::GetFullPath($tempRoot)
    $resolvedTaskTempRoot = [System.IO.Path]::GetFullPath($taskTempRoot)
    if (-not $resolvedTaskTempRoot.StartsWith($resolvedTempRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
        $resolvedTaskTempRoot -ceq $resolvedTempRoot) {
        throw "Refusing to remove an unverified toolchain temporary directory"
    }
    Remove-Item -LiteralPath $resolvedTaskTempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$env:PATH = "$otpBin;$elixirBin;$env:PATH"

if ($PersistUserPath) {
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $userPathParts = @($userPath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    foreach ($requiredPart in @($otpBin, $elixirBin)) {
        if ($userPathParts -notcontains $requiredPart) {
            $userPathParts = @($requiredPart) + $userPathParts
        }
    }
    [Environment]::SetEnvironmentVariable("Path", ($userPathParts -join ';'), "User")
}

$otpExpression = 'erlang:display(erlang:system_info(otp_release)), halt().'
$otpOutput = (& (Join-Path $otpBin "erl.exe") -noshell -eval $otpExpression | Out-String)
if ($LASTEXITCODE -ne 0 -or $otpOutput.Trim() -cne ('"' + $otpMajor + '"')) {
    throw "Erlang verification did not prove repository-pinned OTP $otpVersion"
}

$elixirOutput = (& (Join-Path $elixirBin "elixir.bat") --version | Out-String)
if ($LASTEXITCODE -ne 0 -or
    $elixirOutput -notmatch "(?m)^Elixir\s+$([regex]::Escape($elixirVersion))\s+\(") {
    throw "Elixir verification did not prove repository-pinned version $elixirVersion"
}

$mixOutput = (& (Join-Path $elixirBin "mix.bat") --version | Out-String)
if ($LASTEXITCODE -ne 0 -or
    $mixOutput -notmatch "(?m)^Mix\s+$([regex]::Escape($elixirVersion))\s+\(") {
    throw "Mix verification did not prove repository-pinned version $elixirVersion"
}

Write-Output "Verified content-addressed Erlang/OTP $otpVersion and Elixir/Mix $elixirVersion."
