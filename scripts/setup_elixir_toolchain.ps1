[CmdletBinding()]
param(
    [switch]$PersistUserPath
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$toolchainPath = Join-Path $repoRoot "config/toolchain.json"
$toolchain = Get-Content -LiteralPath $toolchainPath -Raw | ConvertFrom-Json

$elixirVersion = [string]$toolchain.primary.elixir
$otpVersion = [string]$toolchain.primary.erlang_otp
$otpMajor = $otpVersion.Split('.')[0]
$installRoot = Join-Path $env:USERPROFILE ".elixir-install\installs"
$otpBin = Join-Path $installRoot "otp\$otpVersion\bin"
$elixirBin = Join-Path $installRoot "elixir\$elixirVersion-otp-$otpMajor\bin"

if (-not (Test-Path -LiteralPath (Join-Path $otpBin "erl.exe")) -or
    -not (Test-Path -LiteralPath (Join-Path $elixirBin "elixir.bat"))) {
    $installerPath = Join-Path ([System.IO.Path]::GetTempPath()) "uok-elixir-install.bat"
    & curl.exe -fsS -o $installerPath "https://elixir-lang.org/install.bat"
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to download the official Elixir installer"
    }
    & $installerPath "elixir@$elixirVersion" "otp@$otpVersion"
    if ($LASTEXITCODE -ne 0) {
        throw "Official Elixir installer failed with exit code $LASTEXITCODE"
    }
}

$env:PATH = "$otpBin;$elixirBin;$env:PATH"

if ($PersistUserPath) {
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $userPathParts = @($userPath -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $requiredParts = @($otpBin, $elixirBin)
    foreach ($requiredPart in $requiredParts) {
        if ($userPathParts -notcontains $requiredPart) {
            $userPathParts = @($requiredPart) + $userPathParts
        }
    }
    [Environment]::SetEnvironmentVariable("Path", ($userPathParts -join ';'), "User")
}

$otpExpression = 'erlang:display(erlang:system_info(otp_release)), halt().'
& (Join-Path $otpBin "erl.exe") -noshell -eval $otpExpression
if ($LASTEXITCODE -ne 0) {
    throw "Erlang verification failed with exit code $LASTEXITCODE"
}

& (Join-Path $elixirBin "elixir.bat") --version
if ($LASTEXITCODE -ne 0) {
    throw "Elixir verification failed with exit code $LASTEXITCODE"
}

& (Join-Path $elixirBin "mix.bat") --version
if ($LASTEXITCODE -ne 0) {
    throw "Mix verification failed with exit code $LASTEXITCODE"
}
