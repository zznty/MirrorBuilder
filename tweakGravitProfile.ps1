param (
    [Parameter(Mandatory = $true)]
    $profileJson,

    # Base URL for gravit mirrors
    [Parameter()]
    [string]
    $MirrorUrl = "https://mirror.gravitlauncher.com/5.6.x"
)

Import-Module -Name $PSScriptRoot\tweakers.psm1

function Get-ProfileComponentVersion {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]
        $ComponentUid
    )
    
    $profileJson."+components" | Where-Object { $_.uid -eq $ComponentUid } | Select-Object -ExpandProperty version
}

$fabricLoaderVersion = Get-ProfileComponentVersion "net.fabricmc.fabric-loader"
if ($minecraftVersion -ge "1.14.0" -and $fabricLoaderVersion) {
    Invoke-GitGradleBuild "https://github.com/FabricMC/fabric-loader.git" "tags/$fabricLoaderVersion" "$MirrorUrl/patches/FabricLoader.patch" "libraries/net/fabricmc/fabric-loader/$fabricLoaderVersion/fabric-loader-$fabricLoaderVersion.jar"
}

if ($profileJson.mainClass -eq "io.github.zekerzhayard.forgewrapper.installer.Main" -and $minecraftVersion -ge "1.18.0") {
    $secureJarHandler = Get-ChildItem libraries -Recurse -Filter "securejarhandler-*.jar"

    $manifest = Get-ZipEntry $secureJarHandler -Include "META-INF/MANIFEST.MF" | Get-ZipEntryContent

    $gitCommit = $manifest -split "`n" | Where-Object { $_ -like "Git-Commit:*" } | ForEach-Object { $_.Split(":")[1].Trim() }

    Invoke-GitGradleBuild "https://github.com/McModLauncher/securejarhandler.git" $gitCommit ($secureJarHandler -like "*securejarhandler-2.1.2*.jar" ? "https://mirror.gravitlauncher.com/5.5.x/patches/forge/securejarhandler-2.1.27.patch" : "https://mirror.gravitlauncher.com/5.5.x/patches/forge/securejarhandler.patch") $secureJarHandler
}
elseif ($profileJson.mainClass -eq "io.github.zekerzhayard.forgewrapper.installer.Main" -and $minecraftVersion -eq "1.16.5") {
    $modLauncher = Get-ChildItem libraries -Recurse -Filter "modlauncher*.jar"

    Invoke-RestMethod "https://github.com/RetroForge/modlauncher/releases/download/1.8.3-1.16.5-patched1/modlauncher-8.1.3.jar" -OutFile $modLauncher
}

# Cleanroom forge
if ($minecraftVersion -eq "1.12.2" -and (Get-ProfileComponentVersion "net.minecraftforge") -gt "15.24.0.3030") {
    $foundation = $profileJson.classPath -match ".*foundation-.*.jar" | Select-Object -First 1

    Invoke-GitGradleBuild "https://github.com/kappa-maintainer/Foundation.git" "main" "https://zmirror.storage.yandexcloud.net/5.5.x/patches/Foundation.patch" $foundation
}
elseif ($minecraftVersion -eq "1.12.2" -and (Get-ProfileComponentVersion "net.minecraftforge") -gt "15.0.0") {
    $bouncepad = $profileJson.classPath -match ".*bouncepad-.*.jar" | Select-Object -First 1

    Invoke-GitGradleBuild "https://github.com/kappa-maintainer/Bouncepad-cursed.git" "cursed-ASM-Upper" "https://zmirror.storage.yandexcloud.net/5.5.x/patches/Bouncepad.patch" $bouncepad
}

# GTNH lwjgl3ify
if ($minecraftVersion -eq "1.7.10" -and (Get-ProfileComponentVersion "me.eigenraven.lwjgl3ify.forgepatches")) {
    $forgePatches = $profileJson.classPath -match ".*lwjgl3ify-.*-forgePatches\.jar" | Select-Object -First 1

    $rfb = New-TemporaryFile

    Invoke-GitGradleBuild "https://github.com/GTNewHorizons/RetroFuturaBootstrap.git" "master" "$MirrorUrl/patches/rfb.patch" $rfb

    New-Item -Type Directory "forgePatches" -Force | Out-Null

    Expand-Archive $forgePatches -DestinationPath "forgePatches"
    Expand-Archive $rfb -DestinationPath "forgePatches" -Force

    Compress-ZipArchive "forgePatches/*" -DestinationPath $forgePatches -Force
    Move-Item "$forgePatches.zip" $forgePatches -Force

    Remove-Item $rfb, "forgePatches" -Recurse -Force

    $profileJson.jvmArgs += "-Drfb.skipClassLoaderCheck=true"
    $profileJson.jvmArgs = $profileJson.jvmArgs -notmatch "-Djava\.system\.class\.loader"

    # rn metadata provides us with the guava 15 which is missing Runnables required for UniMixins to work
    # TODO remove this
    $guava = $profileJson.classPath -match ".*guava-15.0.jar" | Select-Object -First 1
    if ($guava) {
        $profileJson.classPath = $profileJson.classPath -notmatch ".*guava-15.0.jar"

        New-Item -Type Directory "libraries/com/google/guava/guava/17.0/" -Force | Out-Null
        $guava = "libraries/com/google/guava/guava/17.0/guava-17.0.jar"
        Invoke-RestMethod "https://repo1.maven.org/maven2/com/google/guava/guava/17.0/guava-17.0.jar" -OutFile $guava

        $profileJson.classPath += $guava
    }
}

# launch wrapper only for <=1.12.2 and not lwjgl3
if ($minecraftVersion -le "1.12.2" -and (Get-ProfileComponentVersion "net.minecraftforge") -and -not (Get-ProfileComponentVersion "org.lwjgl3")) {
    $launchWrapper = $profileJson.classPath -match ".*launchwrapper-.*.jar" | Select-Object -First 1
    if (Get-ProfileComponentVersion "io.github.cruciblemc") {
        Invoke-GitGradleBuild "https://github.com/CrucibleMC/LegacyLauncher.git" "bb33a856b1ae2df8b5e008ab1112986bce82b537" "https://zmirror.storage.yandexcloud.net/5.5.x/patches/LegacyLauncher.patch" $launchWrapper
    }
    else {
        # TODO do not hardcode url
        Invoke-RestMethod "https://mirror.gravitlauncher.com/compat/launchwrapper-1.12-5.0.x.jar" -OutFile $launchWrapper
    }
}

if ($minecraftVersion -le "1.7.10" -and $ServerWrapperProfile) {
    $server = $profileJson.classPath -match ".*server-.*.jar" | Select-Object -First 1

    New-Item -Type Directory "server" -Force | Out-Null
    Expand-Archive $server -DestinationPath "server"

    Remove-Item "server\org\apache\logging\log4j\" -Recurse -Force

    $log4jUrls = "https://files.prismlauncher.org/maven/org/apache/logging/log4j/log4j-api/2.0-beta9-fixed/log4j-api-2.0-beta9-fixed.jar", "https://files.prismlauncher.org/maven/org/apache/logging/log4j/log4j-core/2.0-beta9-fixed/log4j-core-2.0-beta9-fixed.jar"
    foreach ($url in $log4jUrls) {
        Invoke-RestMethod $url -OutFile "temp.jar"

        Get-ZipEntry "temp.jar" -Include "org/apache/logging/log4j/*" | Expand-ZipEntry -Destination "server/" 

        Remove-Item "temp.jar"
    }

    Compress-ZipArchive "server/*" -DestinationPath $server -Force
    Move-Item "$server.zip" $server -Force

    Remove-Item "server" -Recurse -Force
}

if ($minecraftVersion -eq "1.16.5" -and $ServerWrapperProfile) {
    $server = $profileJson.classPath -match ".*server-.*.jar" | Select-Object -First 1

    New-Item -Type Directory "server" -Force | Out-Null
    Expand-Archive $server -DestinationPath "server"

    Remove-Item "server\org\apache\logging\log4j\" -Recurse -Force

    $log4jUrls = "https://libraries.minecraft.net/org/apache/logging/log4j/log4j-api/2.15.0/log4j-api-2.15.0.jar", "https://libraries.minecraft.net/org/apache/logging/log4j/log4j-core/2.15.0/log4j-core-2.15.0.jar", "https://libraries.minecraft.net/org/apache/logging/log4j/log4j-slf4j18-impl/2.15.0/log4j-slf4j18-impl-2.15.0.jar"
    foreach ($url in $log4jUrls) {
        $libPath = Join-Path "libraries" -ChildPath (($url | Split-Path -NoQualifier) -replace "^//[\w\.]*/", "")

        New-Item -Type Directory (Split-Path $libPath) -Force | Out-Null
        
        Invoke-RestMethod $url -OutFile $libPath
        
        $profileJson.classPath += $libPath -replace "\\", "/"
    }

    Compress-ZipArchive "server/*" -DestinationPath $server -Force
    Move-Item "$server.zip" $server -Force

    Remove-Item "server" -Recurse -Force
}

if (!$ServerWrapperProfile) {
    foreach ($os in "mustdie", "linux", "macos") {
        foreach ($arch in "x86-64", "x86", "arm64") {
            New-Item -Type Directory "natives/$os/$arch" -Force | Out-Null
        }
    }
}

New-Item -Type Directory "mods" -Force | Out-Null
Write-Output "Place your mods here" | Set-Content "mods/mods.txt"

if ($minecraftVersion -le "1.16.3") {
    # 1.7.10 - 1.16.3
    $authLibPatchUrl = "$MirrorUrl/authlib/LauncherAuthlib1.jar"
}
elseif ($minecraftVersion -lt "1.18.0") {
    # 1.16.4 - 1.17.x
    $authLibPatchUrl = "$MirrorUrl/authlib/LauncherAuthlib2.jar"
}
elseif ($minecraftVersion -lt "1.19.0") {
    # 1.18.x
    $authLibPatchUrl = "$MirrorUrl/authlib/LauncherAuthlib3.jar"
}
elseif ($minecraftVersion -lt "1.20.0") {
    # 1.19.x
    $authLibPatchUrl = "$MirrorUrl/authlib/LauncherAuthlib3-1.19.jar"
}
elseif ($minecraftVersion -lt "1.20.2") {
    # 1.20 - 1.20.1
    $authLibPatchUrl = "$MirrorUrl/authlib/LauncherAuthlib4.jar"
}
elseif ($minecraftVersion -lt "1.20.4") {
    # 1.20.2 - 1.20.3
    $authLibPatchUrl = "$MirrorUrl/authlib/LauncherAuthlib5.jar"
}
else {
    # 1.20.4+
    $authLibPatchUrl = "$MirrorUrl/authlib/LauncherAuthlib6.jar"
}

Write-Debug "Downloading $authLibPatchUrl"

$authLibPatch = "authlib-patch.jar"
Invoke-RestMethod $authLibPatchUrl -OutFile $authLibPatch

Get-ChildItem libraries -Recurse | Where-Object { $_.Name -match "^(authlib.+\.jar)|(server.+\.jar)$" } | ForEach-Object {
    if (!(Get-ZipEntry $_ -Include "com/mojang/authlib/*")) {
        return
    }

    Write-Debug "Patching $_"
    New-Item -Type Directory "authlib" -Force | Out-Null
    Expand-Archive $_ -DestinationPath "authlib"

    Expand-Archive $authLibPatch -DestinationPath "authlib" -Force

    Compress-ZipArchive "authlib/*" -DestinationPath $_ -Force
    Move-Item "$_.zip" $_ -Force

    Remove-Item "authlib" -Recurse -Force
}

Remove-Item $authLibPatch -Force
