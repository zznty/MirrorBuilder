$ErrorActionPreference = "Stop"
$DebugPreference = 'Continue'

Import-Module PSCompression
Import-Module -Name "$PSScriptRoot\utils.psm1"

$uid = "io.github.cruciblemc"
New-Item -ItemType Directory $uid -Force | Out-Null

# Get Crucible 5.4+ (previous versions does not have proper library management so we need to filter them out)
$crucibleVersions = gh release -R "CrucibleMC/Crucible" list --exclude-pre-releases --json "name,tagName,isLatest,publishedAt" | ConvertFrom-Json | Where-Object { $_.tagName -replace "v", "" -ge "5.4" }

@{
    formatVersion = 1;
    name          = "Crucible 1.7.10";
    uid           = $uid;
    recommended   = @($crucibleVersions | Where-Object { $_.isLatest } | Select-Object -ExpandProperty tagName);
} | ConvertTo-Json | Set-Content "$uid/package.json"

@{
    formatVersion = 1;
    name          = "Crucible 1.7.10";
    uid           = $uid;
    versions      = $crucibleVersions | ForEach-Object {
        [PSCustomObject]@{
            releaseTime = $_.publishedAt
            version     = $_.tagName -replace "v", ""
            recommended = $_.isLatest
        }
    }
} | ConvertTo-Json -Depth 100 | Set-Content "$uid/index.json"

$crucibleVersions | ForEach-Object {
    if (Test-Path "$uid/$crucibleVersion.json") {
        return
    }

    $assets = gh release -R "CrucibleMC/Crucible" view $_.tagName --json assets | ConvertFrom-Json | Select-Object -ExpandProperty assets

    $crucibleAsset = $assets | Where-Object { $_.name -like "Crucible-1.7.10-*.jar" }
    $crucibleVersion = $_.tagName -replace "v", "";

    Invoke-WebRequest $crucibleAsset.url -OutFile "temp.jar"

    $jarManifest = Get-JarManifest "temp.jar"

    @{
        formatVersion        = 1;
        name                 = "Crucible 1.7.10";
        uid                  = $uid;
        version              = $crucibleVersion;
        releaseTime          = $_.publishedAt;
        requires             = @(
            [PSCustomObject]@{
                uid    = "net.minecraftforge";
                equals = $jarManifest.'Forge-Version'
            }
        );
        libraries            = $jarManifest.'Crucible-Libs' -split "\s" | ForEach-Object {
            if ($_ -like "io.github.cruciblemc:launchwrapper*") {
                # cuz they decided to fucking rename it and forge ships with regular name 
                $version = $_.Split(":")[2]
                [PSCustomObject]@{
                    name      = $_ -replace "io.github.cruciblemc:launchwrapper", "net.minecraft:launchwrapper";
                    downloads = [PSCustomObject]@{
                        artifact = [PSCustomObject]@{
                            url = "https://github.com/juanmuscaria/maven/raw/master/io/github/cruciblemc/launchwrapper/$version/launchwrapper-$version.jar"
                        }
                    }
                }
            }
            else {
                [PSCustomObject]@{
                    name       = $_;
                    'MMC-hint' = "maven";
                }
            }
        };
        maven                = "https://github.com/juanmuscaria/maven/raw/master/ThermosLibs", "https://github.com/juanmuscaria/maven/raw/master", "https://maven.minecraftforge.net", "https://oss.sonatype.org/content/repositories/snapshots", "https://libraries.minecraft.net";

        mainJar              = [PSCustomObject]@{
            name      = "io.github.cruciblemc:crucible:$($jarManifest.'Implementation-Version')";
            downloads = [PSCustomObject]@{
                artifact = [PSCustomObject]@{
                    url  = $crucibleAsset.url
                    sha1 = Get-FileHash "temp.jar" -Algorithm SHA1 | Select-Object -ExpandProperty Hash
                    size = $crucibleAsset.size
                }
            }
        }
        mainClass            = $jarManifest.'Main-Class';
        jvmArgs              = @("-Dcrucible.skipLibraryVerification=true");
        type                 = $jarManifest.'Implementation-Version' -contains "snapshot" ? "snapshot" : "release";
        order                = 6;
        compatibleJavaMajors = 8, 11, 16, 17
    } | ConvertTo-Json -Depth 100 | Set-Content "$uid/$crucibleVersion.json"

    Remove-Item "temp.jar"
}