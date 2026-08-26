[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$sourceUri =
    "https://msi.nga.mil/api/publications/download?type=view&key=16920959/SFH00000/UpdatedPub150.csv"
$repoRoot = Split-Path -Parent $PSScriptRoot
$referenceRoot = Join-Path $repoRoot "priv/reference"
$catalogPath = Join-Path $referenceRoot "major_seaports.json"
$metadataPath = Join-Path $referenceRoot "major_seaports.metadata.json"
$maximumSourceBytes = 10MB
$maximumCatalogBytes = 2MB

function Read-BoundedHttpsBytes {
    param(
        [Parameter(Mandatory)]
        [Uri]$Uri,

        [Parameter(Mandatory)]
        [int]$MaximumBytes
    )

    if ($Uri.Scheme -ne "https") {
        throw "The public catalog source must use HTTPS."
    }

    $handler = [Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = $false
    $client = [Net.Http.HttpClient]::new($handler, $true)
    $response = $null
    $stream = $null
    $output = [IO.MemoryStream]::new()

    try {
        $response = $client.GetAsync(
            $Uri,
            [Net.Http.HttpCompletionOption]::ResponseHeadersRead
        ).GetAwaiter().GetResult()
        $response.EnsureSuccessStatusCode() | Out-Null

        $declaredLength = $response.Content.Headers.ContentLength
        if ($null -ne $declaredLength -and $declaredLength -gt $MaximumBytes) {
            throw "The public catalog response exceeds the byte limit."
        }

        $stream = $response.Content.ReadAsStream()
        $buffer = [byte[]]::new(81920)

        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            if ($output.Length + $read -gt $MaximumBytes) {
                throw "The public catalog response exceeds the byte limit."
            }

            $output.Write($buffer, 0, $read)
        }

        return ,$output.ToArray()
    }
    finally {
        if ($null -ne $stream) { $stream.Dispose() }
        if ($null -ne $response) { $response.Dispose() }
        $output.Dispose()
        $client.Dispose()
    }
}

$sourceBytes = [byte[]](Read-BoundedHttpsBytes -Uri $sourceUri -MaximumBytes $maximumSourceBytes)

if ($sourceBytes.Length -lt 100000) {
    throw "The official public maritime-port catalog response was unexpectedly small."
}

$sourceText = [Text.Encoding]::UTF8.GetString($sourceBytes).TrimStart([char]0xFEFF)
$sourceRows = @($sourceText | ConvertFrom-Csv)

if ($sourceRows.Count -lt 3000 -or $sourceRows.Count -gt 10000) {
    throw "The public catalog contains an unexpected number of rows: $($sourceRows.Count)."
}
$requiredColumns = @(
    "World Port Index Number",
    "Main Port Name",
    "UN/LOCODE",
    "Country Code",
    "Harbor Size"
)
$availableColumns = @($sourceRows[0].PSObject.Properties.Name)

foreach ($column in $requiredColumns) {
    if ($column -notin $availableColumns) {
        throw "The public catalog is missing required column '$column'."
    }
}

$harborRank = @{
    "Large" = 4
    "Medium" = 3
    "Small" = 2
    "Very Small" = 1
    "" = 0
}

$codedRows = @(
    $sourceRows |
        Where-Object { $_.'UN/LOCODE' -match '^[A-Z]{2}\s?[A-Z0-9]{3}$' } |
        ForEach-Object {
            $referenceCode = $_.'UN/LOCODE' -replace '\s', ''
            $harborScale = [string]$_.'Harbor Size'
            $rank = if ($harborRank.ContainsKey($harborScale)) { $harborRank[$harborScale] } else { 0 }

            [pscustomobject]@{
                reference_code = $referenceCode
                country_code = $referenceCode.Substring(0, 2)
                country_name = ([string]$_.'Country Code').Trim()
                name = ([string]$_.'Main Port Name').Trim()
                harbor_scale = if ($harborScale) { $harborScale.ToLowerInvariant().Replace(' ', '_') } else { "unclassified" }
                catalog_number = ([string]$_.'World Port Index Number') -replace '\.0$', ''
                rank = $rank
            }
        } |
        Where-Object {
            $_.name.Length -ge 2 -and
            $_.name.Length -le 200 -and
            [Text.Encoding]::UTF8.GetByteCount($_.name) -le 400 -and
            $_.country_name.Length -ge 2 -and
            $_.country_name.Length -le 100 -and
            [Text.Encoding]::UTF8.GetByteCount($_.country_name) -le 200
        }
)

$catalog = @(
    $codedRows |
        Group-Object reference_code |
        ForEach-Object {
            $_.Group |
                Sort-Object @{ Expression = "rank"; Descending = $true }, catalog_number, name |
                Select-Object -First 1
        } |
        Sort-Object country_code, @{ Expression = "rank"; Descending = $true }, name, reference_code |
        Select-Object reference_code, country_code, country_name, name, harbor_scale, catalog_number
)

if ($catalog.Count -lt 3000) {
    throw "The derived catalog contains too few standardized seaports: $($catalog.Count)."
}

$duplicateCodes = @($catalog | Group-Object reference_code | Where-Object Count -gt 1)
if ($duplicateCodes.Count -ne 0) {
    throw "The derived catalog contains duplicate standardized codes."
}

New-Item -ItemType Directory -Force -Path $referenceRoot | Out-Null
$catalogJson = $catalog | ConvertTo-Json -Depth 4
$catalogJsonBytes = [Text.Encoding]::UTF8.GetByteCount("$catalogJson`n")
if ($catalogJsonBytes -gt $maximumCatalogBytes) {
    throw "The derived catalog exceeds the byte limit."
}

[IO.File]::WriteAllText($catalogPath, "$catalogJson`n", [Text.UTF8Encoding]::new($false))

$sourceSha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($sourceBytes)).ToLowerInvariant()
$catalogBytes = [IO.File]::ReadAllBytes($catalogPath)
$catalogSha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($catalogBytes)).ToLowerInvariant()
$catalogVersion = "{0}-{1}" -f (Get-Date -AsUTC -Format "yyyy-MM-dd"), $sourceSha256.Substring(0, 12)
$countryCount = @($catalog | Select-Object -ExpandProperty country_code -Unique).Count

$metadata = [ordered]@{
    schema_version = 1
    catalog_version = $catalogVersion
    retrieved_at = (Get-Date -AsUTC -Format "yyyy-MM-ddTHH:mm:ssZ")
    source_role = "official_public_maritime_port_catalog"
    source_uri = $sourceUri
    source_sha256 = $sourceSha256
    selection_rule = "standardized_maritime_location_code_present"
    ranking_rule = "harbor_scale_descending_then_name"
    record_count = $catalog.Count
    country_count = $countryCount
    catalog_sha256 = $catalogSha256
}
$metadataJson = $metadata | ConvertTo-Json -Depth 4
[IO.File]::WriteAllText($metadataPath, "$metadataJson`n", [Text.UTF8Encoding]::new($false))

Write-Output "Created catalog $catalogVersion with $($catalog.Count) ports in $countryCount countries."
