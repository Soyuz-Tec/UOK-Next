[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$modulePath = Join-Path $repoRoot "scripts\security\ArtifactIntegrity.psm1"
Import-Module -Name $modulePath -Force

function Assert-Rejected {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [Parameter(Mandatory = $true)][string]$ExpectedMessage,
        [Parameter(Mandatory = $true)][string]$FailureMessage
    )

    $rejected = $false
    try {
        & $Action
    }
    catch {
        if ($_.Exception.Message -notmatch $ExpectedMessage) {
            throw
        }
        $rejected = $true
    }
    if (-not $rejected) {
        throw $FailureMessage
    }
}

function Add-ZipTextEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.IO.Compression.ZipArchive]$Archive,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Content,
        [Nullable[int]]$ExternalAttributes
    )

    $entry = $Archive.CreateEntry($Name)
    if ($null -ne $ExternalAttributes) {
        $entry.ExternalAttributes = $ExternalAttributes
    }
    $stream = $entry.Open()
    $writer = [System.IO.StreamWriter]::new($stream)
    try {
        $writer.Write($Content)
    }
    finally {
        $writer.Dispose()
    }
}

function New-TestZip {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$EntryName,
        [Nullable[int]]$ExternalAttributes,
        [string]$SecondEntryName
    )

    $file = [System.IO.File]::Open($Path, [System.IO.FileMode]::CreateNew)
    $archive = [System.IO.Compression.ZipArchive]::new(
        $file,
        [System.IO.Compression.ZipArchiveMode]::Create,
        $false
    )
    try {
        Add-ZipTextEntry -Archive $archive -Name $EntryName -Content "approved" `
            -ExternalAttributes $ExternalAttributes
        if (-not [string]::IsNullOrEmpty($SecondEntryName)) {
            Add-ZipTextEntry -Archive $archive -Name $SecondEntryName -Content "approved"
        }
    }
    finally {
        $archive.Dispose()
    }
}

function New-TestTar {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$EntryName,
        [System.Formats.Tar.TarEntryType]$EntryType = [System.Formats.Tar.TarEntryType]::RegularFile,
        [string]$SecondEntryName
    )

    $file = [System.IO.File]::Open($Path, [System.IO.FileMode]::CreateNew)
    $writer = [System.Formats.Tar.TarWriter]::new($file, $false)
    try {
        $entry = [System.Formats.Tar.PaxTarEntry]::new($EntryType, $EntryName)
        if ($EntryType -eq [System.Formats.Tar.TarEntryType]::RegularFile) {
            $entry.DataStream = [System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes("approved"))
        }
        elseif ($EntryType -eq [System.Formats.Tar.TarEntryType]::SymbolicLink) {
            $entry.LinkName = "approved.txt"
        }
        $writer.WriteEntry($entry)
        if (-not [string]::IsNullOrEmpty($SecondEntryName)) {
            $secondEntry = [System.Formats.Tar.PaxTarEntry]::new(
                [System.Formats.Tar.TarEntryType]::RegularFile,
                $SecondEntryName
            )
            $secondEntry.DataStream = [System.IO.MemoryStream]::new(
                [System.Text.Encoding]::UTF8.GetBytes("approved")
            )
            $writer.WriteEntry($secondEntry)
        }
    }
    finally {
        $writer.Dispose()
    }
}

Assert-HttpsUri -Uri "https://github.com/erlang/otp/releases/download/OTP-28.4/otp_win64_28.4.zip"
Assert-Rejected -Action { Assert-HttpsUri -Uri "http://example.invalid/artifact" } `
    -ExpectedMessage "absolute HTTPS URI" `
    -FailureMessage "Plaintext artifact URI was not rejected"

$fixturePath = [System.IO.Path]::GetTempFileName()
try {
    [System.IO.File]::WriteAllText($fixturePath, "approved artifact")
    $approvedSha256 = (Get-FileHash -LiteralPath $fixturePath -Algorithm SHA256).Hash
    $approvedSha512 = (Get-FileHash -LiteralPath $fixturePath -Algorithm SHA512).Hash
    Assert-FileSha256 -Path $fixturePath -ExpectedSha256 $approvedSha256
    Assert-FileSha512 -Path $fixturePath -ExpectedSha512 $approvedSha512

    [System.IO.File]::AppendAllText($fixturePath, " tampered")
    Assert-Rejected -Action {
        Assert-FileSha256 -Path $fixturePath -ExpectedSha256 $approvedSha256
    } -ExpectedMessage "does not match" -FailureMessage "SHA-256 tampering was not rejected"
    Assert-Rejected -Action {
        Assert-FileSha512 -Path $fixturePath -ExpectedSha512 $approvedSha512
    } -ExpectedMessage "does not match" -FailureMessage "SHA-512 tampering was not rejected"
    Assert-Rejected -Action {
        Assert-FileSha256 -Path $fixturePath -ExpectedSha256 "not-a-sha256"
    } -ExpectedMessage "must contain exactly 64" -FailureMessage "Malformed SHA-256 was not rejected"
    Assert-Rejected -Action {
        Assert-FileSha512 -Path $fixturePath -ExpectedSha512 "not-a-sha512"
    } -ExpectedMessage "must contain exactly 128" -FailureMessage "Malformed SHA-512 was not rejected"
}
finally {
    Remove-Item -LiteralPath $fixturePath -Force -ErrorAction SilentlyContinue
}

$tempRoot = [System.IO.Path]::GetTempPath()
$testRoot = Join-Path $tempRoot ("uok-next-artifact-test-" + [guid]::NewGuid().ToString("N"))
$null = New-Item -ItemType Directory -Path $testRoot
try {
    $safeZip = Join-Path $testRoot "safe.zip"
    $safeTar = Join-Path $testRoot "safe.tar"
    New-TestZip -Path $safeZip -EntryName "nested/approved.txt"
    New-TestTar -Path $safeTar -EntryName "nested/approved.txt"
    Expand-SafeZipArchive -ArchivePath $safeZip -DestinationPath (Join-Path $testRoot "safe-zip")
    Expand-SafeTarArchive -ArchivePath $safeTar -DestinationPath (Join-Path $testRoot "safe-tar")

    foreach ($approvedPath in @(
            (Join-Path $testRoot "safe-zip\nested\approved.txt"),
            (Join-Path $testRoot "safe-tar\nested\approved.txt")
        )) {
        if ((Get-Content -LiteralPath $approvedPath -Raw) -cne "approved") {
            throw "Safe archive content was not extracted correctly"
        }
    }

    $zipEscape = Join-Path $testRoot "zip-escape.zip"
    $tarEscape = Join-Path $testRoot "tar-escape.tar"
    New-TestZip -Path $zipEscape -EntryName "../zip-escape.txt"
    New-TestTar -Path $tarEscape -EntryName "../tar-escape.txt"
    Assert-Rejected -Action {
        Expand-SafeZipArchive -ArchivePath $zipEscape -DestinationPath (Join-Path $testRoot "zip-escape")
    } -ExpectedMessage "escapes the extraction directory" `
        -FailureMessage "ZIP traversal entry was not rejected"
    Assert-Rejected -Action {
        Expand-SafeTarArchive -ArchivePath $tarEscape -DestinationPath (Join-Path $testRoot "tar-escape")
    } -ExpectedMessage "escapes the extraction directory" `
        -FailureMessage "TAR traversal entry was not rejected"
    if (Test-Path -LiteralPath (Join-Path $testRoot "zip-escape.txt") -PathType Leaf) {
        throw "ZIP traversal created a file outside the extraction directory"
    }
    if (Test-Path -LiteralPath (Join-Path $testRoot "tar-escape.txt") -PathType Leaf) {
        throw "TAR traversal created a file outside the extraction directory"
    }

    $zipLink = Join-Path $testRoot "zip-link.zip"
    $zipLinkAttributes = [System.BitConverter]::ToInt32(
        [System.BitConverter]::GetBytes([uint32][int64]2717843456),
        0
    )
    New-TestZip -Path $zipLink -EntryName "link" -ExternalAttributes $zipLinkAttributes
    Assert-Rejected -Action {
        Expand-SafeZipArchive -ArchivePath $zipLink -DestinationPath (Join-Path $testRoot "zip-link")
    } -ExpectedMessage "links and special-file entries" `
        -FailureMessage "ZIP symbolic link was not rejected"

    $tarLink = Join-Path $testRoot "tar-link.tar"
    New-TestTar -Path $tarLink -EntryName "link" -EntryType SymbolicLink
    Assert-Rejected -Action {
        Expand-SafeTarArchive -ArchivePath $tarLink -DestinationPath (Join-Path $testRoot "tar-link")
    } -ExpectedMessage "links and special-file entries" `
        -FailureMessage "TAR symbolic link was not rejected"

    Assert-Rejected -Action {
        Expand-SafeZipArchive -ArchivePath $safeZip -DestinationPath (Join-Path $testRoot "zip-size") `
            -MaximumExpandedBytes 1
    } -ExpectedMessage "expanded-size limit" `
        -FailureMessage "ZIP expanded-size limit was not enforced"
    Assert-Rejected -Action {
        Expand-SafeTarArchive -ArchivePath $safeTar -DestinationPath (Join-Path $testRoot "tar-size") `
            -MaximumExpandedBytes 1
    } -ExpectedMessage "expanded-size limit" `
        -FailureMessage "TAR expanded-size limit was not enforced"

    $zipCount = Join-Path $testRoot "zip-count.zip"
    $tarCount = Join-Path $testRoot "tar-count.tar"
    New-TestZip -Path $zipCount -EntryName "one" -SecondEntryName "two"
    New-TestTar -Path $tarCount -EntryName "one" -SecondEntryName "two"
    Assert-Rejected -Action {
        Expand-SafeZipArchive -ArchivePath $zipCount -DestinationPath (Join-Path $testRoot "zip-count") `
            -MaximumEntries 1
    } -ExpectedMessage "entry-count limit" `
        -FailureMessage "ZIP entry-count limit was not enforced"
    Assert-Rejected -Action {
        Expand-SafeTarArchive -ArchivePath $tarCount -DestinationPath (Join-Path $testRoot "tar-count") `
            -MaximumEntries 1
    } -ExpectedMessage "entry-count limit" `
        -FailureMessage "TAR entry-count limit was not enforced"

    $zipDuplicate = Join-Path $testRoot "zip-duplicate.zip"
    $tarDuplicate = Join-Path $testRoot "tar-duplicate.tar"
    New-TestZip -Path $zipDuplicate -EntryName "same" -SecondEntryName "SAME"
    New-TestTar -Path $tarDuplicate -EntryName "same" -SecondEntryName "SAME"
    Assert-Rejected -Action {
        Expand-SafeZipArchive -ArchivePath $zipDuplicate `
            -DestinationPath (Join-Path $testRoot "zip-duplicate")
    } -ExpectedMessage "duplicate destination paths" `
        -FailureMessage "ZIP duplicate destination was not rejected"
    Assert-Rejected -Action {
        Expand-SafeTarArchive -ArchivePath $tarDuplicate `
            -DestinationPath (Join-Path $testRoot "tar-duplicate")
    } -ExpectedMessage "duplicate destination paths" `
        -FailureMessage "TAR duplicate destination was not rejected"

    $existingDestination = Join-Path $testRoot "existing"
    $null = New-Item -ItemType Directory -Path $existingDestination
    Assert-Rejected -Action {
        Expand-SafeZipArchive -ArchivePath $safeZip -DestinationPath $existingDestination
    } -ExpectedMessage "must not already exist" `
        -FailureMessage "Existing extraction destination was not rejected"
}
finally {
    $resolvedTempRoot = [System.IO.Path]::GetFullPath($tempRoot)
    $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
    if (-not $resolvedTestRoot.StartsWith($resolvedTempRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
        $resolvedTestRoot -ceq $resolvedTempRoot) {
        throw "Refusing to remove an unverified artifact-test directory"
    }
    Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output "Artifact-integrity regression test passed."
