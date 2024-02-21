param (
    [Parameter(Mandatory = $true)]
    $profileJson,

    # Base URL for gravit mirrors
    [Parameter()]
    [string]
    $MirrorUrl = "https://mirror.gravitlauncher.com/5.5.x"
)

[version]$minecraftVersion = $profileJson.version

function Get-ProfileComponentVersion {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]
        $ComponentUid
    )
    
    $profileJson."+components" | Where-Object { $_.uid -eq $ComponentUid } | Select-Object -ExpandProperty version
}

function GitGradleBuild {
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $repoUrl,

        [Parameter(Mandatory = $true)]
        [string]
        $repoTag,

        [Parameter(Mandatory = $true)]
        [string]
        $patchUrl,

        [Parameter(Mandatory = $true)]
        [string]
        $outputPath
    )
    $buildPath = New-TemporaryFile | ForEach-Object { Remove-Item $_; New-Item -Type Directory $_ }
    
    git clone --mirror $repoUrl "$buildPath/.git"
    git -C "$buildPath" config --unset core.bare
    git -C "$buildPath" checkout $repoTag
    git -C "$buildPath" switch -c branch
    
    Invoke-RestMethod "$MirrorUrl/$patchUrl" | git -C "$buildPath" apply -3 | Out-Null

    (Get-Content "$buildPath/build.gradle") | ForEach-Object { $_ -replace "fromTag .*$", "" } | Set-Content "$buildPath/build.gradle"
    
    $gradle = "$buildPath/gradlew"
    if ($IsWindows) {
        $gradle += ".bat"
    }
    
    Write-Debug "Running gradle build"
    
    $prevPwd = $PWD

    Set-Location $buildPath
    
    & $gradle build | Out-Null

    Set-Location $prevPwd
    
    $jarPath = Get-ChildItem (Join-Path $buildPath -ChildPath "build/libs/") -Exclude "*-sources.jar" | Select-Object -First 1
    
    Copy-Item $jarPath -Force -Destination $outputPath
    
    Remove-Item $buildPath -Recurse -Force -ErrorAction Ignore
}

$fabricLoaderVersion = Get-ProfileComponentVersion "net.fabricmc.fabric-loader"
if ($minecraftVersion -ge "1.14.0" -and $fabricLoaderVersion) {
    GitGradleBuild "https://github.com/FabricMC/fabric-loader.git" "tags/$fabricLoaderVersion" "patches/FabricLoader.patch" "libraries/net/fabricmc/fabric-loader/$fabricLoaderVersion/fabric-loader-$fabricLoaderVersion.jar"
}

if ($profileJson.mainClass -eq "io.github.zekerzhayard.forgewrapper.installer.Main" -and $minecraftVersion -ge "1.18.0") {
    $secureJarHandler = Get-ChildItem libraries -Recurse -Filter "securejarhandler-*.jar"

    $manifest = Get-ZipEntry $secureJarHandler -Include "META-INF/MANIFEST.MF" | Get-ZipEntryContent

    $gitCommit = $manifest -split "`n" | Where-Object { $_ -like "Git-Commit:*" } | ForEach-Object { $_.Split(":")[1].Trim() }

    GitGradleBuild "https://github.com/McModLauncher/securejarhandler.git" $gitCommit ($secureJarHandler -like "*securejarhandler-2.1.2*.jar" ? "patches/forge/securejarhandler-2.1.27.patch" : "patches/forge/securejarhandler.patch") $secureJarHandler
}
elseif ($profileJson.mainClass -eq "io.github.zekerzhayard.forgewrapper.installer.Main" -and $minecraftVersion -eq "1.16.5") {
    $modLauncher = Get-ChildItem libraries -Recurse -Filter "modlauncher*.jar"

    Invoke-RestMethod "https://github.com/RetroForge/modlauncher/releases/download/1.8.3-1.16.5-patched1/modlauncher-8.1.3.jar" -OutFile $modLauncher
}

if ($minecraftVersion -le "1.12.2" -and (Get-ProfileComponentVersion "net.minecraftforge")) {
    $launchWrapper = Get-ChildItem libraries -Recurse -Filter "launchwrapper-*.jar"
    # TODO do not hardcode url
    Invoke-RestMethod "https://mirror.gravitlauncher.com/compat/launchwrapper-1.12-5.0.x.jar" -OutFile $launchWrapper
}

if ($minecraftVersion -eq "1.7.10") {
    # 1.7.10 meta uses log4j-2.0-beta9-fixed which is not compatible with gravit authlib 
    $version = "2.17.2"
    $corePath = "libraries/org/apache/logging/log4j/log4j-core/$version/log4j-core-$version.jar"
    $apiPath = "libraries/org/apache/logging/log4j/log4j-api/$version/log4j-api-$version.jar"
    $helpersPath = $corePath | Split-Path | Join-Path -ChildPath "log4j-core-$version-helpers-2.0-beta9.jar"

    $corePath, $apiPath | Split-Path | ForEach-Object { New-Item -Type Directory $_ -Force } | Out-Null

    Invoke-RestMethod "https://repo1.maven.org/maven2/org/apache/logging/log4j/log4j-core/$version/log4j-core-$version.jar" -OutFile $corePath
    Invoke-RestMethod "https://repo1.maven.org/maven2/org/apache/logging/log4j/log4j-api/$version/log4j-api-$version.jar" -OutFile $apiPath

    Copy-Item (Join-Path $PSScriptRoot -ChildPath ($helpersPath | Split-Path -Leaf)) -Destination $helpersPath -Force

    for ($i = 0; $i -lt $profileJson.classPath.Count; $i++) {
        if ($profileJson.classPath[$i] -like "*log4j-api*") {
            $profileJson.classPath[$i] = $apiPath
        }
        elseif ($profileJson.classPath[$i] -like "*log4j-core*") {
            $profileJson.classPath[$i] = $corePath
        }
    }

    $profileJson.classPath += $helpersPath -replace "\\", "/"
}

foreach ($os in "mustdie", "linux", "macos") {
    foreach ($arch in "x86-64", "x86", "arm64") {
        New-Item -Type Directory "natives/$os/$arch" -Force | Out-Null
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
elseif ($minecraftVersion -eq "1.19.0") {
    # 1.19.0
    $authLibPatchUrl = "$MirrorUrl/authlib/LauncherAuthlib3-1.19.jar"
}
elseif ($minecraftVersion -lt "1.20.0") {
    # 1.18.x - 1.19.x except 1.19.0
    $authLibPatchUrl = "$MirrorUrl/authlib/LauncherAuthlib3.jar"
}
elseif ($minecraftVersion -lt "1.20.2") {
    # 1.20.x - 1.20.1
    $authLibPatchUrl = "$MirrorUrl/authlib/LauncherAuthlib4.jar"
}
elseif ($minecraftVersion -eq "1.20.2") {
    # 1.20.2
    $authLibPatchUrl = "$MirrorUrl/authlib/LauncherAuthlib5.jar"
}
else {
    # 1.20.3+
    $authLibPatchUrl = "$MirrorUrl/authlib/LauncherAuthlib6.jar"
}

Write-Debug "Downloading $authLibPatchUrl"

$authLibPatch = "authlib-patch.jar"
Invoke-RestMethod $authLibPatchUrl -OutFile $authLibPatch

$authLib = Get-ChildItem libraries -Recurse -Filter "authlib-*.jar"

New-Item -Type Directory "authlib" -Force | Out-Null
Expand-Archive $authLib -DestinationPath "authlib"

Expand-Archive $authLibPatch -DestinationPath "authlib" -Force

Compress-Archive "authlib/*" -DestinationPath $authLib -Force

Remove-Item "authlib", $authLibPatch -Recurse -Force