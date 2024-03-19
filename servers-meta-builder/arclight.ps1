$ErrorActionPreference = "Stop"
$DebugPreference = 'Continue'

Import-Module PSCompression
Import-Module -Name "$PSScriptRoot\utils.psm1"

$uid = "io.izzel.arclight"
New-Item -ItemType Directory $uid -Force | Out-Null

$arclightBranches = Invoke-RestMethod "https://files.hypoglycemia.icu/v1/files/arclight/minecraft"

$arclightVersions = $arclightBranches.files | ForEach-Object {
    $versionsStable = Invoke-RestMethod "$($_.link)/versions-stable/"
    $versionsSnapshot = Invoke-RestMethod "$($_.link)/versions-snapshot/"

    $mcVersion = $_.name

    ($versionsStable.files + $versionsSnapshot.files) | ForEach-Object {
        Add-Member -InputObject $_ -NotePropertyName "mcVersion" -NotePropertyValue $mcVersion

        $_
    }
} | ForEach-Object { $_ } | ForEach-Object {
    $version = Invoke-RestMethod $_.link

    $mcVersion = $_.mcVersion

    $version.files | Where-Object { $_.name -eq "forge" } | ForEach-Object {
        Add-Member -InputObject $_ -NotePropertyName "mcVersion" -NotePropertyValue $mcVersion
        Add-Member -InputObject $_ -NotePropertyName "longVersion" -NotePropertyValue "$mcVersion-$($_.key.Split("/")[-2])-$($_.name)"

        $_
    }
}

@{
    formatVersion = 1;
    name          = "ArcLight";
    uid           = $uid;
    recommended   = $arclightVersions | Where-Object { $_.key -like "/arclight/branches/*/versions-stable/*/forge" } | ForEach-Object { $_.longVersion }
} | ConvertTo-Json | Set-Content "$uid/package.json"

@{
    formatVersion = 1;
    name          = "ArcLight";
    uid           = $uid;
    versions      = $arclightVersions | ForEach-Object {
        [PSCustomObject]@{
            releaseTime = $_.'last-modified';
            version     = $_.longVersion
            recommended = $_.key -like "/arclight/branches/*/versions-stable/*/forge"
            sha1        = $_.permlink -replace "^.*objects/", ""
        }
    }
} | ConvertTo-Json -Depth 100 | Set-Content "$uid/index.json"

$arclightVersions | ForEach-Object {
    if (Test-Path "$uid/$($_.longVersion).json") {
        return
    }

    Invoke-WebRequest $_.link -OutFile "temp.jar"

    $installerManifest = Get-ZipEntry "temp.jar" -Include "META-INF/installer.json" | Get-ZipEntryContent | ConvertFrom-Json -AsHashtable

    $jarManifest = Get-JarManifest "temp.jar"

    @{
        formatVersion = 1;
        name          = "ArcLight";
        uid           = $uid;
        version       = $_.longVersion
        requires      = @(
            [PSCustomObject]@{
                uid    = "net.minecraft";
                equals = $installerManifest.installer.minecraft
            },
            [PSCustomObject]@{
                uid    = "net.minecraftforge";
                equals = $installerManifest.installer.forge
            }
        );
        libraries     = $installerManifest.libraries.GetEnumerator() | ForEach-Object {
            $parts = $_.Key.Split(":")

            $extension = "jar"
            if ($parts[2] -like "*@zip") {
                $parts[2] = $parts[2].Split("@")[0]
                $extension = "zip"
            }
    
            $dirArray = $parts[0].Split(".") + $parts[1] + $parts[2];
            if ($parts.Length -gt 3) {
                $fileName = "$($parts[1])-$($parts[2])-$($parts[3]).$extension"
            }
            else {
                $fileName = "$($parts[1])-$($parts[2]).$extension"
            }
            $filePath = $dirArray + $fileName -join "/"

            [PSCustomObject]@{
                name      = $_.Key;
                downloads = [PSCustomObject]@{
                    artifact = [PSCustomObject]@{
                        url  = "https://arclight.hypertention.cn/$filePath"
                        sha1 = $_.Value
                    }
                }
            }
        };

        mainJar       = [PSCustomObject]@{
            name      = "io.izzel.arclight:server:$($_.longVersion)";
            downloads = [PSCustomObject]@{
                artifact = [PSCustomObject]@{
                    url  = $_.link
                    sha1 = Get-FileHash "temp.jar" -Algorithm SHA1 | Select-Object -ExpandProperty Hash
                    size = Get-Item "temp.jar" | Select-Object -ExpandProperty Length
                }
            }
        };
        mainClass     = $jarManifest.'Main-Class';
        order         = 6;
        type          = $jarManifest.'Implementation-Version' -contains "snapshot" ? "snapshot" : "release";
        releaseTime   = Get-Date $jarManifest.'Implementation-Timestamp' -Format "yyyy-MM-ddTHH:mm:ss";
        compatibleJavaMajors = 17
    } | ConvertTo-Json -Depth 100 | Set-Content "$uid/$($_.longVersion).json"

    Remove-Item "temp.jar"
}