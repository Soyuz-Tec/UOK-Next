function Assert-HttpsUri {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Uri)

    $parsed = $null
    if (-not [System.Uri]::TryCreate($Uri, [System.UriKind]::Absolute, [ref]$parsed) -or
        $parsed.Scheme -cne [System.Uri]::UriSchemeHttps) {
        throw "Artifact URI must be an absolute HTTPS URI"
    }
}

function Assert-FileDigest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][ValidateSet("SHA256", "SHA512")][string]$Algorithm,
        [Parameter(Mandatory = $true)][string]$ExpectedDigest
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Artifact does not exist at the expected path"
    }

    $requiredLength = if ($Algorithm -ceq "SHA256") { 64 } else { 128 }
    if ($ExpectedDigest -cnotmatch "^[0-9A-Fa-f]{$requiredLength}$") {
        throw "Expected $Algorithm must contain exactly $requiredLength hexadecimal characters"
    }

    $actualDigest = (Get-FileHash -LiteralPath $Path -Algorithm $Algorithm).Hash
    if ($actualDigest -cne $ExpectedDigest.ToUpperInvariant()) {
        throw "Artifact $Algorithm does not match the repository-approved digest"
    }
}

function Assert-FileSha256 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256
    )

    Assert-FileDigest -Path $Path -Algorithm "SHA256" -ExpectedDigest $ExpectedSha256
}

function Assert-FileSha512 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedSha512
    )

    Assert-FileDigest -Path $Path -Algorithm "SHA512" -ExpectedDigest $ExpectedSha512
}

function Assert-NoReparseInstallPaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string[]]$RelativePaths
    )

    $resolvedRoot = [System.IO.Path]::GetFullPath($Root)
    $rootItem = Get-Item -LiteralPath $resolvedRoot -Force
    if (($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Installed artifact paths must not contain reparse points"
    }
    foreach ($relativePath in $RelativePaths) {
        $current = $resolvedRoot
        foreach ($part in @($relativePath -split '[\\/]' | Where-Object { $_ -ne '' })) {
            $current = Join-Path $current $part
            $resolvedCurrent = [System.IO.Path]::GetFullPath($current)
            if (-not $resolvedCurrent.StartsWith(
                    $resolvedRoot + [System.IO.Path]::DirectorySeparatorChar,
                    [System.StringComparison]::OrdinalIgnoreCase
                )) {
                throw "Installed artifact path escapes its content-addressed root"
            }
            $item = Get-Item -LiteralPath $resolvedCurrent -Force
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Installed artifact paths must not contain reparse points"
            }
        }
    }
}

function Assert-RestrictedInstallAcl {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Root)

    $allowed = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $null = $allowed.Add([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
    $null = $allowed.Add('S-1-5-18')
    $null = $allowed.Add('S-1-5-32-544')
    $acl = Get-Acl -LiteralPath $Root
    $owner = $acl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value
    if (-not $allowed.Contains($owner)) {
        throw "Installed artifact directory has an unapproved owner"
    }

    [int64]$writeMask = [int64][System.Security.AccessControl.FileSystemRights]::Write -bor
        [int64][System.Security.AccessControl.FileSystemRights]::Delete -bor
        [int64][System.Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor
        [int64][System.Security.AccessControl.FileSystemRights]::ChangePermissions -bor
        [int64][System.Security.AccessControl.FileSystemRights]::TakeOwnership
    $rules = $acl.GetAccessRules(
        $true,
        $true,
        [System.Security.Principal.SecurityIdentifier]
    )
    foreach ($rule in $rules) {
        $writable = ([int64]$rule.FileSystemRights -band $writeMask) -ne 0
        if ($rule.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Allow -and
            $writable -and -not $allowed.Contains($rule.IdentityReference.Value)) {
            throw "Installed artifact directory grants write access to an unapproved identity"
        }
    }
}

function New-VerifiedInstallReceipt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$SourceSha256
    )

    if ($SourceSha256 -cnotmatch '^[0-9A-F]{64}$') {
        throw "Install receipt SHA-256 must contain 64 uppercase hexadecimal characters"
    }
    $receiptPath = Join-Path $Root '.uok-next-source-sha256'
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($SourceSha256 + "`n")
    $receipt = [System.IO.File]::Open(
        $receiptPath,
        [System.IO.FileMode]::CreateNew,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::None
    )
    try {
        $receipt.Write($bytes, 0, $bytes.Length)
    }
    finally {
        $receipt.Dispose()
    }
}

function Assert-VerifiedInstallDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$SourceSha256,
        [Parameter(Mandatory = $true)][string[]]$ExpectedRelativePaths
    )

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        throw "Content-addressed install directory does not exist"
    }
    $receiptName = '.uok-next-source-sha256'
    foreach ($relativePath in @($receiptName) + $ExpectedRelativePaths) {
        if (-not (Test-Path -LiteralPath (Join-Path $Root $relativePath) -PathType Leaf)) {
            throw "Content-addressed install is missing '$relativePath'"
        }
    }
    Assert-NoReparseInstallPaths -Root $Root -RelativePaths (@($receiptName) + $ExpectedRelativePaths)
    Assert-RestrictedInstallAcl -Root $Root
    if ((Get-Content -LiteralPath (Join-Path $Root $receiptName) -Raw).Trim() -cne $SourceSha256) {
        throw "Content-addressed install receipt does not match the repository digest"
    }
}

function New-EmptyExtractionDirectory {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$DestinationPath)

    if (Test-Path -LiteralPath $DestinationPath) {
        throw "Archive extraction destination must not already exist"
    }

    $resolvedDestination = [System.IO.Path]::GetFullPath($DestinationPath)
    $null = [System.IO.Directory]::CreateDirectory($resolvedDestination)
    return $resolvedDestination
}

function Resolve-SafeArchiveEntryPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DestinationPath,
        [Parameter(Mandatory = $true)][string]$EntryName
    )

    if ([string]::IsNullOrWhiteSpace($EntryName) -or $EntryName.Contains([char]0) -or
        $EntryName.Contains(':')) {
        throw "Archive entry has an invalid path"
    }

    $separator = [System.IO.Path]::DirectorySeparatorChar
    $normalizedName = $EntryName.Replace('/', $separator).Replace('\', $separator)
    if ([System.IO.Path]::IsPathRooted($normalizedName)) {
        throw "Archive entry path must be relative"
    }

    $resolvedRoot = [System.IO.Path]::GetFullPath($DestinationPath).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    )
    $rootPrefix = $resolvedRoot + $separator
    $resolvedEntry = [System.IO.Path]::GetFullPath((Join-Path $resolvedRoot $normalizedName))
    if (-not $resolvedEntry.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Archive entry escapes the extraction directory"
    }

    return $resolvedEntry
}

function Copy-BoundedArchiveEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.IO.Stream]$Source,
        [Parameter(Mandatory = $true)][string]$DestinationPath,
        [Parameter(Mandatory = $true)][long]$ExpectedLength
    )

    $parent = Split-Path -Parent $DestinationPath
    $null = [System.IO.Directory]::CreateDirectory($parent)
    $destination = [System.IO.File]::Open(
        $DestinationPath,
        [System.IO.FileMode]::CreateNew,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::None
    )
    try {
        $buffer = [byte[]]::new(81920)
        [long]$copied = 0
        while (($read = $Source.Read($buffer, 0, $buffer.Length)) -gt 0) {
            if ($read -gt ($ExpectedLength - $copied)) {
                throw "Archive entry expanded beyond its declared length"
            }
            $destination.Write($buffer, 0, $read)
            $copied += $read
        }
        if ($copied -ne $ExpectedLength) {
            throw "Extracted archive entry length does not match its header"
        }
    }
    finally {
        $destination.Dispose()
    }
}

function Expand-SafeZipArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ArchivePath,
        [Parameter(Mandatory = $true)][string]$DestinationPath,
        [ValidateRange(1, 100000)][int]$MaximumEntries = 10000,
        [ValidateRange(1, 4294967296)][long]$MaximumExpandedBytes = 1073741824
    )

    if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) {
        throw "ZIP archive does not exist at the expected path"
    }
    $resolvedDestination = New-EmptyExtractionDirectory -DestinationPath $DestinationPath
    $archive = [System.IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        if ($archive.Entries.Count -gt $MaximumEntries) {
            throw "ZIP archive exceeds the entry-count limit"
        }
        [long]$expandedBytes = 0
        $seenTargets = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::OrdinalIgnoreCase
        )
        foreach ($entry in $archive.Entries) {
            if ($entry.IsEncrypted) {
                throw "Encrypted ZIP entries are not accepted"
            }
            if ($entry.Length -gt ($MaximumExpandedBytes - $expandedBytes)) {
                throw "ZIP archive exceeds the expanded-size limit"
            }
            $expandedBytes += $entry.Length

            $target = Resolve-SafeArchiveEntryPath -DestinationPath $resolvedDestination -EntryName $entry.FullName
            if (-not $seenTargets.Add($target)) {
                throw "Archive contains duplicate destination paths"
            }
            [uint32]$attributes = ([int64]$entry.ExternalAttributes -band 0xFFFFFFFFL)
            $unixType = ($attributes -shr 16) -band 0xF000
            $isDirectory = [string]::IsNullOrEmpty($entry.Name)
            if ($unixType -notin @(0, 0x4000, 0x8000) -or
                ($isDirectory -and $unixType -eq 0x8000) -or
                (-not $isDirectory -and $unixType -eq 0x4000)) {
                throw "ZIP links and special-file entries are not accepted"
            }
            if ($isDirectory) {
                $null = [System.IO.Directory]::CreateDirectory($target)
                continue
            }

            $source = $entry.Open()
            try {
                Copy-BoundedArchiveEntry -Source $source -DestinationPath $target -ExpectedLength $entry.Length
            }
            finally {
                $source.Dispose()
            }
        }
    }
    finally {
        $archive.Dispose()
    }
}

function Expand-SafeTarArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ArchivePath,
        [Parameter(Mandatory = $true)][string]$DestinationPath,
        [switch]$Gzip,
        [ValidateRange(1, 100000)][int]$MaximumEntries = 10000,
        [ValidateRange(1, 4294967296)][long]$MaximumExpandedBytes = 1073741824
    )

    if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) {
        throw "TAR archive does not exist at the expected path"
    }
    $resolvedDestination = New-EmptyExtractionDirectory -DestinationPath $DestinationPath
    $file = [System.IO.File]::OpenRead($ArchivePath)
    $stream = if ($Gzip) {
        [System.IO.Compression.GZipStream]::new($file, [System.IO.Compression.CompressionMode]::Decompress, $true)
    }
    else {
        $file
    }
    $reader = [System.Formats.Tar.TarReader]::new($stream, $true)
    try {
        $entryCount = 0
        [long]$expandedBytes = 0
        $seenTargets = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::OrdinalIgnoreCase
        )
        while ($null -ne ($entry = $reader.GetNextEntry($false))) {
            $entryCount++
            if ($entryCount -gt $MaximumEntries) {
                throw "TAR archive exceeds the entry-count limit"
            }
            $target = Resolve-SafeArchiveEntryPath -DestinationPath $resolvedDestination -EntryName $entry.Name
            if (-not $seenTargets.Add($target)) {
                throw "Archive contains duplicate destination paths"
            }
            if ($entry.EntryType -eq [System.Formats.Tar.TarEntryType]::Directory) {
                $null = [System.IO.Directory]::CreateDirectory($target)
                continue
            }
            if ($entry.EntryType -notin @(
                    [System.Formats.Tar.TarEntryType]::RegularFile,
                    [System.Formats.Tar.TarEntryType]::V7RegularFile
                )) {
                throw "TAR links and special-file entries are not accepted"
            }
            if ($entry.Length -gt ($MaximumExpandedBytes - $expandedBytes)) {
                throw "TAR archive exceeds the expanded-size limit"
            }
            $expandedBytes += $entry.Length
            Copy-BoundedArchiveEntry -Source $entry.DataStream -DestinationPath $target -ExpectedLength $entry.Length
        }
    }
    finally {
        $reader.Dispose()
        if ($Gzip) {
            $stream.Dispose()
        }
        $file.Dispose()
    }
}

Export-ModuleMember -Function Assert-HttpsUri, Assert-FileSha256, Assert-FileSha512, New-VerifiedInstallReceipt, Assert-VerifiedInstallDirectory, Expand-SafeZipArchive, Expand-SafeTarArchive
