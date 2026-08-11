[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$policy = Get-Content -LiteralPath (Join-Path $repoRoot "config/code_policy.json") -Raw | ConvertFrom-Json
$exceptionCatalog = Get-Content -LiteralPath (Join-Path $repoRoot "config/code_size_exceptions.json") -Raw | ConvertFrom-Json

if ($policy.schema_version -ne 1 -or $exceptionCatalog.schema_version -ne 1) {
    throw "Unsupported code-discipline schema version"
}

$today = [DateTime]::UtcNow.Date
$exceptions = @{}
foreach ($exception in @($exceptionCatalog.exceptions)) {
    $requiredFields = @("path", "owner", "reason", "expires_on", "replacement_plan")
    foreach ($requiredField in $requiredFields) {
        if ([string]::IsNullOrWhiteSpace($exception.$requiredField)) {
            throw "Code-size exception is missing '$requiredField'"
        }
    }
    $normalizedPath = ([string]$exception.path).Replace('\', '/')
    if ($exceptions.ContainsKey($normalizedPath)) {
        throw "Duplicate code-size exception for '$normalizedPath'"
    }
    $expiry = [DateTime]::ParseExact([string]$exception.expires_on, "yyyy-MM-dd", [Globalization.CultureInfo]::InvariantCulture)
    if ($expiry.Date -lt $today) {
        throw "Code-size exception for '$normalizedPath' expired on $($exception.expires_on)"
    }
    $exceptions[$normalizedPath] = $exception
}

$reviewFindings = @()
$maximumFindings = @()
$checkedFiles = 0
$repoRootWithSeparator = $repoRoot.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar

function Get-RepositoryRelativePath {
    param([Parameter(Mandatory = $true)][string]$FullName)

    $canonicalPath = [System.IO.Path]::GetFullPath($FullName)
    if (-not $canonicalPath.StartsWith($repoRootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Source path is outside the repository: '$canonicalPath'"
    }

    return $canonicalPath.Substring($repoRootWithSeparator.Length).Replace('\', '/')
}

foreach ($filePolicy in @($policy.file_policies)) {
    foreach ($relativeRoot in @($filePolicy.roots)) {
        $sourceRoot = Join-Path $repoRoot $relativeRoot
        if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) {
            continue
        }
        $files = Get-ChildItem -LiteralPath $sourceRoot -File -Recurse
        foreach ($file in $files) {
            if (@($filePolicy.extensions) -notcontains $file.Extension) {
                continue
            }
            $relativePath = Get-RepositoryRelativePath -FullName $file.FullName
            $pathForMatch = "/$relativePath"
            $excluded = @($filePolicy.excluded_path_fragments | Where-Object { $pathForMatch.Contains($_) }).Count -gt 0
            if ($excluded) {
                continue
            }
            $checkedFiles += 1
            $lineCount = @(Get-Content -LiteralPath $file.FullName).Count
            if ($lineCount -gt [int]$filePolicy.maximum_lines -and -not $exceptions.ContainsKey($relativePath)) {
                $maximumFindings += "$relativePath ($lineCount > $($filePolicy.maximum_lines))"
            }
            elseif ($lineCount -gt [int]$filePolicy.review_lines) {
                $reviewFindings += "$relativePath ($lineCount > $($filePolicy.review_lines))"
            }
        }
    }
}

foreach ($finding in $reviewFindings) {
    Write-Warning "Cohesion review required: $finding"
}

if ($maximumFindings.Count -gt 0) {
    throw "Production source files exceed maximum size without an active exception: $($maximumFindings -join '; ')"
}

Write-Output "Code-discipline verification passed for $checkedFiles production source files with $($exceptions.Count) active exceptions."
