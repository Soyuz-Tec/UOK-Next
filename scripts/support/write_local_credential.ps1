function Get-UokCloneLocalCredentialPath {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$RepositoryRoot)

    if ($env:OS -ne "Windows_NT") {
        throw "Clone-local credential storage currently requires Windows"
    }

    $localApplicationData = [Environment]::GetFolderPath(
        [Environment+SpecialFolder]::LocalApplicationData
    )
    if ([string]::IsNullOrWhiteSpace($localApplicationData)) {
        throw "Windows LocalApplicationData is unavailable"
    }

    $normalizedRepository = [IO.Path]::GetFullPath($RepositoryRoot).Replace("\", "/")
    $normalizedRepository = $normalizedRepository.TrimEnd('/').ToLowerInvariant()
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $hashBytes = $sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes($normalizedRepository))
    }
    finally {
        $sha256.Dispose()
    }
    $cloneHash = ([BitConverter]::ToString($hashBytes)).Replace("-", "").ToLowerInvariant()

    $credentialRoot = Join-Path $localApplicationData "UOK-Next\credentials"
    $credentialPath = Join-Path $credentialRoot "$cloneHash\uok-db-password"
    $resolvedRoot = [IO.Path]::GetFullPath($credentialRoot).TrimEnd('\') + '\'
    $resolvedCredential = [IO.Path]::GetFullPath($credentialPath)

    if (-not $resolvedCredential.StartsWith(
            $resolvedRoot,
            [StringComparison]::OrdinalIgnoreCase
        )) {
        throw "The clone-local credential path escaped Windows LocalApplicationData"
    }

    $resolvedCredential
}

function Write-UokCloneLocalCredential {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Value
    )

    if ($env:OS -ne "Windows_NT") {
        throw "Clone-local credential ACL enforcement currently requires Windows"
    }

    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $system = [Security.Principal.SecurityIdentifier]::new("S-1-5-18")
    $administrators = [Security.Principal.SecurityIdentifier]::new("S-1-5-32-544")
    $allowedSids = @($currentUser, $system, $administrators)
    $directory = Split-Path -Parent $Path

    [IO.Directory]::CreateDirectory($directory) | Out-Null

    $aclTool = Join-Path $env:SystemRoot "System32\icacls.exe"
    $directoryRules = @($allowedSids | ForEach-Object { "*$($_.Value):(OI)(CI)F" })
    & $aclTool $directory "/inheritance:r" "/grant:r" $directoryRules | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "The clone-local credential directory ACL could not be restricted"
    }
    Assert-UokRestrictedCredentialAcl -Path $directory -AllowedSids $allowedSids

    [IO.File]::WriteAllText($Path, $Value)
    $fileRules = @($allowedSids | ForEach-Object { "*$($_.Value):F" })
    & $aclTool $Path "/inheritance:r" "/grant:r" $fileRules | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "The clone-local database credential ACL could not be restricted"
    }

    Assert-UokRestrictedCredentialAcl -Path $Path -AllowedSids $allowedSids
}

function Assert-UokRestrictedCredentialAcl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][Security.Principal.SecurityIdentifier[]]$AllowedSids
    )

    $expected = @($AllowedSids | ForEach-Object { $_.Value } | Sort-Object -Unique)
    $actual = @()

    foreach ($rule in (Get-Acl -LiteralPath $Path).Access) {
        if ($rule.IsInherited -or
            $rule.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow) {
            throw "The clone-local database credential has an inherited or denied ACL entry"
        }

        $sid = $rule.IdentityReference.Translate(
            [Security.Principal.SecurityIdentifier]
        ).Value

        if ($sid -notin $expected) {
            throw "The clone-local database credential is accessible to an unexpected principal"
        }

        $actual += $sid
    }

    if ((Compare-Object $expected ($actual | Sort-Object -Unique)).Count -ne 0) {
        throw "The clone-local database credential ACL is incomplete"
    }
}
