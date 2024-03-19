param (
    [Parameter(Mandatory = $true)]
    [string]
    $VersionName,

    [Parameter(Mandatory = $true)]
    [string]
    $ComponentUid,

    # Mirror URL
    [Parameter(Mandatory = $true)]
    [string]
    $MirrorUrl
)

try {
    $profileJson = Invoke-RestMethod -Uri "$MirrorUrl/$VersionName.json"
}
catch {
    return "0.0.0"
}

$profileJson."+components" | Where-Object { $_.uid -eq $ComponentUid } | Select-Object -ExpandProperty version -First 1