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

$profileJson = Invoke-RestMethod -Uri "$MirrorUrl/clients/$VersionName.json" 

$profileJson."+components" | Where-Object { $_.uid -eq $ComponentUid } | Select-Object -ExpandProperty version -First 1