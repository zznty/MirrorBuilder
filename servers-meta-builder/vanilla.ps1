$ErrorActionPreference = "Stop"
$DebugPreference = 'Continue'

Import-Module PSCompression
Import-Module -Name "$PSScriptRoot\utils.psm1"

$uid = "net.minecraft";
New-Item -ItemType Directory $uid -Force | Out-Null

$mojangVersions = Get-Content "$PSScriptRoot/meta-upstream/mojang/version_manifest_v2.json" | ConvertFrom-Json

$mojangVersions.versions = $mojangVersions.versions | Where-Object { $_.type -eq "release" }

@{
    formatVersion = 1;
    name          = "Minecraft";
    uid           = $uid;
    recommended   = @($mojangVersions.latest.release)
} | ConvertTo-Json | Set-Content "$uid/package.json"

@{
    formatVersion = 1;
    name          = "Minecraft";
    uid           = $uid;
    versions      = $mojangVersions.versions | ForEach-Object {
        [PSCustomObject]@{
            releaseTime = $_.releaseTime;
            version     = $_.id
            recommended = $_.id -eq $mojangVersions.latest.release
            sha1        = $_.url -match "/\b([a-f0-9]{40})\b/" ? $matches[1] : $null
        }
    }
} | ConvertTo-Json | Set-Content "$uid/index.json"

$mojangVersions.versions | ForEach-Object {
    if (Test-Path "$uid/$($_.id).json") {
        return
    }

    $versionInfo = Get-Content "$PSScriptRoot/meta-upstream/mojang/versions/$($_.id).json" | ConvertFrom-Json

    if (!$versionInfo.downloads.server.url) {
        return
    }

    Invoke-RestMethod $versionInfo.downloads.server.url -OutFile "temp.jar"

    if (Get-ZipEntry "temp.jar" -Include "META-INF/main-class") {
        # wrapped server jar

        $metaJson = @{
            formatVersion        = 1;
            order                = -2;
            name                 = "Minecraft";
            releaseTime          = $versionInfo.releaseTime;
            uid                  = $uid;
            version              = $_.id;
            type                 = $_.type;
            sha1                 = $_.url -match "/\b([a-f0-9]{40})\b/" ? $matches[1] : $null
            libraries            = Get-ZipEntry "temp.jar" -Include "META-INF/libraries.list" | Get-ZipEntryContent | ForEach-Object {
                $parts = $_ -split "\t"
                [PSCustomObject]@{
                    name      = $parts[1]
                    downloads = [PSCustomObject]@{
                        artifact = [PSCustomObject]@{
                            sha256 = $parts[0];
                            url    = "https://libraries.minecraft.net/$($parts[2])"
                            size   = Get-ZipEntry "temp.jar" -Include "META-INF/libraries/$($parts[2])" | ForEach-Object { $_.Length }
                        }
                    }
                }
            };
            mainClass            = Get-ZipEntry "temp.jar" -Include "META-INF/main-class" | Get-ZipEntryContent;
            mainJar              = [PSCustomObject]@{
                name      = "net.minecraft:server:$($_.id)"
                downloads = [PSCustomObject]@{
                    artifact = [PSCustomObject]@{
                        url         = $versionInfo.downloads.server.url
                        sha1        = $versionInfo.downloads.server.sha1
                        size        = $versionInfo.downloads.server.size
                        archivePath = "META-INF/versions/" + (Get-ZipEntry "temp.jar" -Include "META-INF/versions.list" | Get-ZipEntryContent | ForEach-Object { $_ -split "\t" | Select-Object -Last 1 })
                    }
                }
            };
            compatibleJavaMajors = @($versionInfo.javaVersion.majorVersion)
        }
    }
    else {
        $jarManifest = Get-JarManifest "temp.jar"

        $metaJson = @{
            formatVersion        = 1;
            order                = -2;
            name                 = "Minecraft";
            releaseTime          = $versionInfo.releaseTime;
            uid                  = $uid;
            version              = $_.id;
            type                 = $_.type;
            sha1                 = $_.url -match "/\b([a-f0-9]{40})\b/" ? $matches[1] : $null;
            mainClass            = $jarManifest.'Main-Class';
            mainJar       = [PSCustomObject]@{
                name      = "net.minecraft:server:$($_.id)"
                downloads = [PSCustomObject]@{
                    artifact = [PSCustomObject]@{
                        url         = $versionInfo.downloads.server.url
                        sha1        = $versionInfo.downloads.server.sha1
                        size        = $versionInfo.downloads.server.size
                    }
                }
            };
            compatibleJavaMajors = @($versionInfo.javaVersion.majorVersion)
        }
    }

    $metaJson | ConvertTo-Json -Depth 100 | Set-Content "$uid/$($_.id).json"

    Remove-Item "temp.jar"
}