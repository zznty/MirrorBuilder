$ErrorActionPreference = "Stop"
$DebugPreference = 'Continue'

Import-Module PSCompression
Import-Module -Name "$PSScriptRoot\utils.psm1"

$uid = "net.fabricmc.fabric-loader";

Get-UpstreamComponent $uid

Get-ChildItem $uid -Exclude "index.json","package.json" | ForEach-Object {
    $json = Get-Content $_ | ConvertFrom-Json

    $json.mainClass = "net.fabricmc.loader.impl.launch.server.FabricServerLauncher"

    $json | ConvertTo-Json | Set-Content $_
}