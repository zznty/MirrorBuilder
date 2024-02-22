param (
    [Parameter(Mandatory = $true)]
    [string]
    $ComponentUid,

    [Parameter(Mandatory = $true)]
    [string]
    $MMCPatchDir,

    [Parameter()]
    [hashtable]
    $Requires = @{}
)

$indexJson = Get-Content (Join-Path $MMCPatchDir -ChildPath "mmc-pack.json") | ConvertFrom-Json

$versions = $indexJson.components | Where-Object { $_.uid -eq $ComponentUid }
$versions = $versions | Where-Object {
    $result = $true
    foreach ($require in $_.cachedRequires) {
        if ($Requires.$($require.uid)) {
            $result = $result -and $Requires.$($require.uid) -eq $require.equals
        }
    }

    $result
}

$versions | Select-Object -ExpandProperty cachedVersion -First 1