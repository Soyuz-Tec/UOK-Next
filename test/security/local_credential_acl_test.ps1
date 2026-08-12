[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $repoRoot "scripts\support\write_local_credential.ps1")

$developmentConfig = Get-Content -LiteralPath (Join-Path $repoRoot "config\dev.exs") -Raw
if ($developmentConfig -match 'show_sensitive_data_on_connection_error\s*:\s*true') {
    throw "Development database errors must not disclose connection credentials"
}

$qualificationScript = Get-Content -LiteralPath `
    (Join-Path $repoRoot "scripts\deploy_local_qualification.ps1") -Raw
if ($qualificationScript -match 'party_onboarding_access_code\s*=') {
    throw "The qualification receipt must not disclose the local access code"
}

$tempRoot = [IO.Path]::GetTempPath()
$testRoot = Join-Path $tempRoot ("uok-next-credential-test-" + [guid]::NewGuid().ToString("N"))
$credentialPath = Join-Path $testRoot "uok-db-password"

try {
    $cloneCredential = Get-UokCloneLocalCredentialPath -RepositoryRoot $repoRoot
    $identityCredential = Get-UokCloneLocalCredentialPath `
        -RepositoryRoot $repoRoot -CredentialName "uok-local-identity.json"
    $localApplicationData = [Environment]::GetFolderPath(
        [Environment+SpecialFolder]::LocalApplicationData
    )
    if (-not $cloneCredential.StartsWith(
            ([IO.Path]::GetFullPath($localApplicationData).TrimEnd('\') + '\'),
            [StringComparison]::OrdinalIgnoreCase
        ) -or $cloneCredential.StartsWith(
            ([IO.Path]::GetFullPath($repoRoot).TrimEnd('\') + '\'),
            [StringComparison]::OrdinalIgnoreCase
        )) {
        throw "The supported clone credential path is not isolated from the repository"
    }
    if ([IO.Path]::GetFileName($identityCredential) -cne "uok-local-identity.json" -or
        [IO.Path]::GetDirectoryName($identityCredential) -cne
            [IO.Path]::GetDirectoryName($cloneCredential)) {
        throw "Named clone-local credentials must remain in the same protected clone directory"
    }

    Write-UokCloneLocalCredential -Path $credentialPath -Value ("a" * 64)

    if ((Read-UokCloneLocalCredential -Path $credentialPath) -cne ("a" * 64)) {
        throw "The clone-local credential content was not written exactly"
    }

    $rules = @((Get-Acl -LiteralPath $credentialPath).Access)
    if ($rules.Count -ne 3 -or @($rules | Where-Object IsInherited).Count -ne 0) {
        throw "The clone-local credential did not receive exactly three explicit ACL entries"
    }
}
finally {
    $resolvedTempRoot = [IO.Path]::GetFullPath($tempRoot)
    $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)

    if (-not $resolvedTestRoot.StartsWith(
            $resolvedTempRoot,
            [StringComparison]::OrdinalIgnoreCase
        ) -or $resolvedTestRoot -ceq $resolvedTempRoot) {
        throw "Refusing to remove an unverified credential-test directory"
    }

    Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output "Clone-local credential ACL regression test passed."
