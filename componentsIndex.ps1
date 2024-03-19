param (
    [Parameter(Mandatory = $true)]
    [string]
    $ComponentUid,

    [switch]
    $Recommended,

    [Parameter()]
    [hashtable]
    $Requires = @{},

    [switch]
    $IncludeSnapshots,

    # Meta URL
    [Parameter()]
    [string]
    $MetaUrl = "https://meta.prismlauncher.org/v1"
)
if ($MetaUrl.EndsWith(".zip")) {
    Invoke-RestMethod -Uri "$MetaUrl" -OutFile "meta.zip"

    Import-Module PSCompression

    $indexJson = Get-ZipEntry -Path meta.zip -Include "$ComponentUid/index.json" | Get-ZipEntryContent | ConvertFrom-Json

    Remove-Item meta.zip
}
else {
    $indexJson = Invoke-RestMethod -Uri "$MetaUrl/$ComponentUid/index.json"
}

$versions = $Recommended ? ($indexJson.versions | Where-Object { $_.recommended }) : $indexJson.versions
$versions = $IncludeSnapshots ? $versions : ($versions | Where-Object { !$_.type -or $_.type -ne "snapshot" })
$versions = $versions | Where-Object {
    $result = $true
    foreach ($require in $_.requires) {
        if ($Requires.$($require.uid)) {
            $result = $result -and $Requires.$($require.uid) -eq $require.equals
        }
    }

    $result
}

$versions | Select-Object -ExpandProperty version -First 1