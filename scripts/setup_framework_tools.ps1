[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$toolchainPath = Join-Path $repoRoot "config/toolchain.json"
$toolchain = Get-Content -LiteralPath $toolchainPath -Raw | ConvertFrom-Json

$elixirVersion = [string]$toolchain.primary.elixir
$otpVersion = [string]$toolchain.primary.erlang_otp
$otpMajor = $otpVersion.Split('.')[0]
$phoenixVersion = [string]$toolchain.primary.phoenix_new
$installRoot = Join-Path $env:USERPROFILE ".elixir-install\installs"
$otpBin = Join-Path $installRoot "otp\$otpVersion\bin"
$elixirBin = Join-Path $installRoot "elixir\$elixirVersion-otp-$otpMajor\bin"
$mixPath = Join-Path $elixirBin "mix.bat"

if (-not (Test-Path -LiteralPath $mixPath -PathType Leaf)) {
    throw "Pinned Mix executable is missing. Run scripts/setup_elixir_toolchain.ps1 first."
}

$env:PATH = "$otpBin;$elixirBin;$env:PATH"

& $mixPath local.hex --force
if ($LASTEXITCODE -ne 0) {
    throw "Hex installation failed with exit code $LASTEXITCODE"
}

& $mixPath local.rebar --force
if ($LASTEXITCODE -ne 0) {
    throw "Rebar installation failed with exit code $LASTEXITCODE"
}

& $mixPath archive.install hex phx_new $phoenixVersion --force
if ($LASTEXITCODE -ne 0) {
    throw "Phoenix generator installation failed with exit code $LASTEXITCODE"
}

& $mixPath phx.new --version
if ($LASTEXITCODE -ne 0) {
    throw "Phoenix generator verification failed with exit code $LASTEXITCODE"
}

