$ErrorActionPreference = "Stop"
$DebugPreference = 'Continue'

$uid = "net.neoforged";
New-Item -ItemType Directory $uid -Force | Out-Null

$forgeVersions = Get-Content "$PSScriptRoot/meta-upstream/neoforge/derived_index.json" -Raw | ConvertFrom-Json -AsHashtable

foreach ($badVersion in ($forgeVersions.versions.Keys | Where-Object {
            $forgeParts = $_ -replace "_", "-" -split "-"
            try {
                return [version]$forgeParts[0] -lt "1.21.0"
            } catch { # skip snapshots ans stuff, dont have intentions to support those that violate version spec
                return $true
            }
        })) {
    Write-Debug "Skipping $badVersion"
    $forgeVersions.versions.Remove($badVersion)
}

@{
    formatVersion = 1;
    name          = "NeoForge";
    uid           = $uid;
    recommended   = $forgeVersions.versions.Values | Where-Object { $_.recommended } | Select-Object -ExpandProperty longversion
} | ConvertTo-Json | Set-Content "$uid/package.json"

@{
    formatVersion = 1;
    name          = "NeoForge";
    uid           = $uid;
    versions      = $forgeVersions.versions.Values | ForEach-Object {
        [PSCustomObject]@{
            releaseTime = (Test-Path "$PSScriptRoot/meta-upstream/neoforge/version_manifests/$($_.longversion).json") ? (Get-Content "$PSScriptRoot/meta-upstream/neoforge/version_manifests/$($_.longversion).json" | ConvertFrom-Json | Select-Object -ExpandProperty releaseTime) : $null;
            version     = $_.longversion
            recommended = $_.recommended
            sha1        = Get-FileHash "$PSScriptRoot/meta-upstream/neoforge/files_manifests/$($_.longversion).json" -Algorithm SHA1 | Select-Object -ExpandProperty Hash
            requires    = @(
                [PSCustomObject]@{
                    uid    = "net.minecraft";
                    equals = $_.mcversion
                }
            )
        }
    }
} | ConvertTo-Json -Depth 100 | Set-Content "$uid/index.json"

$forgeVersions.versions.GetEnumerator() | ForEach-Object {
    if (Test-Path "$uid/$($_.version).json") {
        return
    }
    
    $forgeVersion = $_.Value
    $manifestPath = "$PSScriptRoot/meta-upstream/neoforge/installer_manifests/$($_.Key).json"
    $installerInfoPath = "$PSScriptRoot/meta-upstream/neoforge/installer_info/$($_.Key).json"
    
    if (!(Test-Path $manifestPath)) {
        Write-Debug "Installer manifest not found for $($forgeVersion.longversion)"
        # i dont care
        return
    }
    
    $installerInfo = Get-Content $installerInfoPath | ConvertFrom-Json
    $installerProfile = Get-Content $manifestPath | ConvertFrom-Json
    
    [version]$mcVersion = $forgeVersion.mcversion -replace "_", "-" -split "-" | Select-Object -First 1
    
    # build system installer
    
    $versionInfo = Get-Content "$PSScriptRoot/meta-upstream/neoforge/version_manifests/$($_.Key).json" | ConvertFrom-Json
    
    $metaJson = @{
        formatVersion        = 1;
        name                 = "NeoForge";
        uid                  = $uid;
        version              = $forgeVersion.longversion;
        type                 = $versionInfo.type;
        releaseTime          = $versionInfo.releaseTime;
        order                = 5;
        requires             = @(
            [PSCustomObject]@{
                uid    = "net.minecraft";
                equals = $forgeVersion.mcversion
            }
        );
        compatibleJavaMajors = $mcVersion -ge "1.20.5" ? @(21) : 17, 21;
        mainClass            = "io.github.zekerzhayard.forgewrapper.installer.Main";
        minecraftArguments   = $versionInfo.arguments.game -ireplace "^(?<kind>(neo)?forge)client$", '${kind}server' -join " ";
        mavenFiles           = @([PSCustomObject]@{
                name      = "net.neoforged:neoforge:$($forgeVersion.longversion):installer";
                downloads = [PSCustomObject]@{
                    artifact = [PSCustomObject]@{
                        url  = "https://maven.neoforged.net/releases/net/neoforged/neoforge/$($forgeVersion.longversion)/neoforge-$($forgeVersion.longversion)-installer.jar";
                        sha1 = $installerInfo.sha1hash;
                        size = $installerInfo.size;
                    }
                }
            }) + ($installerProfile.libraries | ForEach-Object {
                if ($_.name -like "net.neoforged:neoforge:*:universal") {
                    $_.downloads.artifact.url = "https://maven.neoforged.net/releases/net/neoforged/neoforge/$($forgeVersion.longversion)/neoforge-$($forgeVersion.longversion)-universal.jar"
                }
                $_
            });
        libraries            = @([PSCustomObject]@{
                name      = "io.github.zekerzhayard:ForgeWrapper:1.0-zznty"
                downloads = [PSCustomObject]@{
                    artifact = [PSCustomObject]@{
                        url = "https://github.com/zznty/ForgeWrapper/releases/latest/download/ForgeWrapper.jar";
                    }
                }
            }) + ($versionInfo.libraries | Where-Object { $_.name -notlike "org.apache.logging.log4j*" } | ForEach-Object {
                if ($_.name -eq "net.neoforged:neoforge:$($forgeVersion.longversion)") {
                    $_.downloads.artifact.url = "https://maven.neoforged.net/releases/net/neoforged/neoforge/$($forgeVersion.longversion)/neoforge-$($forgeVersion.longversion)-universal.jar"
                }
                $_
            })
    }
    
    $metaJson | ConvertTo-Json -Depth 100 | Set-Content "$uid/$($forgeVersion.longversion).json"
}
