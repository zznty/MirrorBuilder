$ErrorActionPreference = "Stop"
$DebugPreference = 'Continue'

$legacyVersions = "1.1", "1.2.3", "1.2.4", "1.2.5", "1.3.2", "1.4.1", "1.4.2", "1.4.3", "1.4.4", "1.4.5", "1.4.6", "1.4.7", "1.5", "1.5.1", "1.5.2", "1.6.1", "1.6.2", "1.6.3", "1.6.4", "1.7.10", "1.7.10-pre4", "1.7.2", "1.8", "1.8.8", "1.8.9", "1.9", "1.9.4", "1.10", "1.10.2", "1.11", "1.11.2", "1.12", "1.12.1", "1.12.2"
$badVersions = @("1.12.2-14.23.5.2851")

$uid = "net.minecraftforge";
New-Item -ItemType Directory $uid -Force | Out-Null

$forgeVersions = Get-Content "$PSScriptRoot/meta-upstream/forge/derived_index.json" -Raw | ConvertFrom-Json -AsHashtable

foreach ($badVersion in ($forgeVersions.versions.Keys | Where-Object {
            $forgeParts = $_ -replace "_", "-" -split "-"
            foreach ($badVersion in $badVersions) {
                $badParts = $badVersion -split "-"
                if ([version]$forgeParts[0] -eq $badParts[0] -and [version]$forgeParts[1] -le $badParts[1]) {
                    return $true
                }
            }
            return [version]$forgeParts[0] -ge "1.20.3"
        })) {
    Write-Debug "Skipping $badVersion"
    $forgeVersions.versions.Remove($badVersion)
}

@{
    formatVersion = 1;
    name          = "Forge";
    uid           = $uid;
    recommended   = $forgeVersions.versions.Values | Where-Object { $_.recommended } | Select-Object -ExpandProperty version
} | ConvertTo-Json | Set-Content "$uid/package.json"

@{
    formatVersion = 1;
    name          = "Forge";
    uid           = $uid;
    versions      = $forgeVersions.versions.Values | ForEach-Object {
        [PSCustomObject]@{
            releaseTime = (Test-Path "$PSScriptRoot/meta-upstream/forge/version_manifests/$($_.longversion).json") ? (Get-Content "$PSScriptRoot/meta-upstream/forge/version_manifests/$($_.longversion).json" | ConvertFrom-Json | Select-Object -ExpandProperty releaseTime) : $null;
            version     = $_.version
            recommended = $_.recommended
            sha1        = Get-FileHash "$PSScriptRoot/meta-upstream/forge/files_manifests/$($_.longversion).json" -Algorithm SHA1 | Select-Object -ExpandProperty Hash
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
    $manifestPath = "$PSScriptRoot/meta-upstream/forge/installer_manifests/$($_.Key).json"
    $installerInfoPath = "$PSScriptRoot/meta-upstream/forge/installer_info/$($_.Key).json"

    if (!(Test-Path $manifestPath)) {
        Write-Debug "Installer manifest not found for $($forgeVersion.longversion)"
        # i dont care
        return
    }

    $installerInfo = Get-Content $installerInfoPath | ConvertFrom-Json
    $installerProfile = Get-Content $manifestPath | ConvertFrom-Json

    [version]$mcVersion = $forgeVersion.mcversion -replace "_", "-" -split "-" | Select-Object -First 1

    if ($legacyVersions -match ($forgeVersion.mcversion -replace "_", "-")) {
        # Modernized installer

        $versionInfo = $installerProfile.versionInfo

        $metaJson = @{
            formatVersion = 1;
            name          = "Forge";
            uid           = $uid;
            version       = $forgeVersion.version -replace "_", "-";
            type          = $versionInfo.type;
            releaseTime   = $versionInfo.time;
            order         = 5;
            requires      = @(
                [PSCustomObject]@{
                    uid    = "net.minecraft";
                    equals = $forgeVersion.mcversion -replace "_", "-"
                }
            );
            libraries     = $versionInfo.libraries | ForEach-Object {
                if ($_.name -like "net.minecraftforge:forge:*" -or $_.name -like "net.minecraftforge:minecraftforge:*") {
                    $_.name = "net.minecraftforge:forge:$($forgeVersion.longversion -replace "_", "-"):universal"
                }
                [PSCustomObject]@{
                    name = $_.name;
                    url  = $_.url;
                }
            }
        }
    }
    else {
        # build system installer

        $versionInfo = Get-Content "$PSScriptRoot/meta-upstream/forge/version_manifests/$($_.Key).json" | ConvertFrom-Json

        $metaJson = @{
            formatVersion      = 1;
            name               = "Forge";
            uid                = $uid;
            version            = $forgeVersion.version;
            type               = $versionInfo.type;
            releaseTime        = $versionInfo.releaseTime;
            order              = 5;
            requires           = @(
                [PSCustomObject]@{
                    uid    = "net.minecraft";
                    equals = $forgeVersion.mcversion
                }
            );
            mainClass          = "io.github.zekerzhayard.forgewrapper.installer.Main";
            minecraftArguments = ("--launchTarget", ($mcVersion -ge "1.18.0" ? "forgeserver" : "fmlserver"), "--fml.forgeVersion", $forgeVersion.version, "--fml.mcVersion", $forgeVersion.mcversion, "--fml.forgeGroup", "net.minecraftforge", "--fml.mcpVersion", ($installerProfile.data.MCP_VERSION.server ?? $versionInfo.arguments.game[-1]) -replace "'", "") -join " "
            mavenFiles         = @([PSCustomObject]@{
                    name      = "net.minecraftforge:forge:$($forgeVersion.longversion):installer";
                    downloads = [PSCustomObject]@{
                        artifact = [PSCustomObject]@{
                            url  = "https://maven.minecraftforge.net/net/minecraftforge/forge/$($forgeVersion.longversion)/forge-$($forgeVersion.longversion)-installer.jar";
                            sha1 = $installerInfo.sha1hash;
                            size = $installerInfo.size;
                        }
                    }
                }) + ($installerProfile.libraries | ForEach-Object {
                    if ($_.name -like "net.minecraftforge:forge:*:universal") {
                        $_.downloads.artifact.url = "https://maven.minecraftforge.net/net/minecraftforge/forge/$($forgeVersion.longversion)/forge-$($forgeVersion.longversion)-universal.jar"
                    }
                    $_
                });
            libraries          = @([PSCustomObject]@{
                    name      = "io.github.zekerzhayard:ForgeWrapper:1.0-zznty"
                    downloads = [PSCustomObject]@{
                        artifact = [PSCustomObject]@{
                            url = "https://github.com/zznty/ForgeWrapper/releases/latest/download/ForgeWrapper.jar";
                        }
                    }
                }) + ($versionInfo.libraries | Where-Object { $_.name -notlike "org.apache.logging.log4j*" } | ForEach-Object {
                    if ($_.name -eq "net.minecraftforge:forge:$($forgeVersion.longversion)") {
                        $_.downloads.artifact.url = "https://maven.minecraftforge.net/net/minecraftforge/forge/$($forgeVersion.longversion)/forge-$($forgeVersion.longversion)-universal.jar"
                    }
                    $_
                })
        }

        if ($mcVersion -eq "1.16.5") {
            $metaJson.minecraftArguments += ("--gameDir", ".") -join " "
        }
    }

    if ($mcVersion  -ge "1.18.0") {
        $metaJson.compatibleJavaMajors = 17
    }
    elseif ($mcVersion -ge "1.17.0") {
        $metaJson.compatibleJavaMajors = 16, 17
    }
    elseif ($mcVersion -ge "1.16.0") {
        $metaJson.compatibleJavaMajors = 8, 11, 16, 17
    }
    else {
        $metaJson.compatibleJavaMajors = 8
    }

    $metaJson | ConvertTo-Json -Depth 100 | Set-Content "$uid/$($forgeVersion.version).json"
}