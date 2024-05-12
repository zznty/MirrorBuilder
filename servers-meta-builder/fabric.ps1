$ErrorActionPreference = "Stop"
$DebugPreference = 'Continue'

Import-Module PSCompression
Import-Module -Name "$PSScriptRoot\utils.psm1"

$uid = "net.fabricmc.intermediary";

Get-UpstreamComponent $uid