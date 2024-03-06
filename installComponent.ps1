param (
    # Component UID to install
    [Parameter(Mandatory = $true)]
    [string]
    $ComponentUid,

    # Component Version to install
    [Parameter()]
    [string]
    $CompoentVersion,

    # Meta URL
    [Parameter()]
    [string]
    $MetaUrl = "https://meta.prismlauncher.org/v1",

    # Determines if GravitTweaks should be run
    [switch]
    $SkipGravitTweaks,

    # Determines if local mmc metadata is provided at mmc/patches/
    [switch]
    $MMCPatch,

    [switch]
    $ChildProcess
)

$ErrorActionPreference = "Stop"
$DebugPreference = 'Continue'

$meta = $MMCPatch ? (Get-Content "mmc/patches/$ComponentUid.json" | ConvertFrom-Json) : (Invoke-RestMethod -Uri "$MetaUrl/$ComponentUid/$CompoentVersion.json")

if ($MMCPatch) {
    $CompoentVersion = $meta.version
}

$profileJsonPath = "profile.json"
if (!(Test-Path $profileJsonPath -PathType Leaf)) {
    New-Item $profileJsonPath -Value "{}" | Out-Null
}

$profileJson = Get-Content $profileJsonPath | ConvertFrom-Json -AsHashtable

if ($profileJson."+components" | Where-Object { $_.uid -eq $ComponentUid -and $_.version -eq $CompoentVersion }) {
    Write-Debug "Component $ComponentUid ($CompoentVersion) is already installed"
    exit 1
}

foreach ($requiredComponent in $meta.requires) {
    if ($profileJson."+components" | Where-Object { $_.uid -eq $requiredComponent.uid }) {
        Write-Debug "Required component $($requiredComponent.uid) is already installed"
        continue
    }
    
    $requiredComponentVersion = $requiredComponent.equals

    if ($requiredComponent.suggests) {
        $requiredComponentVersion = $MMCPatch ? $requiredComponent.suggests : (pwsh $PSScriptRoot\componentsIndex.ps1 -ComponentUid $requiredComponent.uid)
    }
    
    if ($null -eq $requiredComponentVersion) {
        Write-Error "Required component $($requiredComponent.uid) does not have a version to install nor currently installed"
        exit 1
    }
    
    pwsh $PSCommandPath -ComponentUid $requiredComponent.uid -CompoentVersion $requiredComponentVersion -ChildProcess -SkipGravitTweaks -MMCPatch:$($MMCPatch.IsPresent)
    if ($LastExitCode -ne 0) {
        exit $LastExitCode
    }
    $profileJson = Get-Content $profileJsonPath | ConvertFrom-Json -AsHashtable
}

Write-Debug "Installing $($meta.name) - $($meta.version)"

New-Item -Type Directory libraries -Force | Out-Null

Write-Debug "Fetching libraries"

function Get-Library {
    param (
        [Parameter(Mandatory = $true)]
        $library,
        [Parameter(Mandatory = $false)]
        [string]
        $OutFile = $null
    )
    $parts = $library.name.Split(":")

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

    if ($library."MMC-hint" -eq "local") {
        New-Item -Type Directory "libraries/$($dirArray -join "/")" -Force | Out-Null
        Copy-Item "mmc/libraries/$fileName" "libraries/$filePath" -Force | Out-Null

        return "libraries/$filePath"
    }

    if (!$library.url -and !$library.downloads.artifact.url) {
        $library | Add-Member "url" "https://libraries.minecraft.net/"
    }

    $url = $library.downloads.artifact.url ?? "$($library.url.TrimEnd("/"))/$filePath"

    if ($library.natives) {
        Get-NativeLibraries $library

        if (!$library.downloads.artifact) {
            return $null
        }
    }

    if ($url -notlike "https://*") {
        return "libraries/$url"
    }
    
    if ([string]::IsNullOrEmpty($OutFile)) {
        $OutFile = "libraries/$filePath"
    }
    # $library.name -like "io.github.zekerzhayard:ForgeWrapper:*" -or 
    if ((Test-Path $OutFile)) {
        Write-Debug "Skipping $($library.name)"
        return $OutFile
    }
    
    Write-Debug "Downloading $($library.name) - $url"
    
    if ($library.name -match "^[\w\.]*:([\w\.(?!natives)]*-){1,2}natives-(macos|linux|windows)(-(arm32|arm64|x86))?:[\w\.]*:?[\w\.]*$") {
        Invoke-RestMethod -Uri $url -OutFile temp

        Get-ZipEntry temp -Exclude "META-INF/*" -Type Archive | ForEach-Object { 
            $path = "natives/$($_.RelativePath -replace "windows", "mustdie" -replace "osx", "macos" -replace "x64", "x86-64")"
            New-Item -ItemType Directory ($path | Split-Path) -Force | Out-Null
            $_ | Get-ZipEntryContent -AsByteStream | Set-Content -Path $path -AsByteStream
         }

        Remove-Item temp

        return $null
    }

    New-Item -Type Directory "libraries/$($dirArray -join "/")" -Force | Out-Null
    
    Invoke-RestMethod -Uri $url -OutFile $OutFile
    
    return $OutFile
}

function Get-NativeLibraries {
    param (
        [Parameter(Mandatory = $true)]
        $library
    )
    
    foreach ($nativeLibrary in $library.natives.PSObject.Properties) {
        $url = $library.downloads.classifiers."$($nativeLibrary.Value -replace "\$\{arch\}", "64")".url

        Write-Debug "Downloading native $($library.name) - $url"

        if (!$url) {
            Write-Host "No native for $($nativeLibrary.Value)"
            continue
        }

        Invoke-RestMethod $url -OutFile temp

        $parts = $nativeLibrary.Name.Split("-")

        $dir = "natives/$($parts[0] -replace "windows", "mustdie" -replace "osx", "macos")/$($parts.Length -gt 1 ? $parts[1] : "x86-64")"

        New-Item -Type Directory $dir -Force | Out-Null

        Get-ZipEntry temp -Exclude "META-INF/*" | Expand-ZipEntry -Destination $dir -Force
    }

    Remove-Item temp
}

foreach ($library in $meta.libraries) {
    $path = Get-Library $library

    if ($path) {
        $profileJson.classPath += @($path)
    }
}

if ($meta.mainJar) {
    $profileJson.classPath += @(Get-Library $meta.mainJar)
}

if ($meta."+jvmArgs") {
    $profileJson."+jvmArgs" += $meta."+jvmArgs"
}

$componentManifest = [PSCustomObject]@{
    uid     = $ComponentUid;
    version = $CompoentVersion
}

$profileJson."+components" += @($componentManifest)

$profileJson.title = "$($meta.name) $($meta.version)"
$profileJson.uuid = "$(New-Guid)"
if ($ComponentUid -eq "net.minecraft") {
    $profileJson.version = $meta.version
    $profileJson.assetIndex = $meta.version
    $profileJson.dir = $meta.version
}
$profileJson.assetDir = "assets"
$profileJson.info = "Server description"
$profileJson.mainClass = $meta.mainClass

if ($meta.compatibleJavaMajors) {
    $profileJson.minJavaVersion = $meta.compatibleJavaMajors[0]
    $profileJson.recommendJavaVersion = $meta.compatibleJavaMajors[-1]
    $profileJson.maxJavaVersion = 999 # default
}
$profileJson.classLoaderConfig = "LAUNCHER" # default

$profileJson.update = @("servers.dat")
$profileJson.updateVerify = "libraries", "mods", "natives"

$profileJson.clientArgs = $meta.minecraftArguments -split " "
if ($meta."+tweakers") {
    foreach ($tweaker in $meta."+tweakers") {
        $profileJson.clientArgs += "--tweakClass", $tweaker
    }
}

if ($ChildProcess -or $null -eq $meta.mainClass) {
    $profileJson | ConvertTo-Json | Out-File $profileJsonPath
    Write-Host "Installed $($meta.name) - $($meta.version)"
    exit
}

$profileJson.jvmArgs = "-XX:+DisableAttachMechanism", "-Djava.library.path=natives"

[version]$minecraftVersion = $profileJson.version

if ($minecraftVersion -le [version]"1.12.2" -and -not $MMCPatch) {
    $profileJson.jvmArgs += "-XX:+UseConcMarkSweepGC", "-XX:+CMSIncrementalMode"
}
elseif ($minecraftVersion -le [version]"1.18") {
    $profileJson.jvmArgs += "-XX:+UseG1GC", "-XX:+UnlockExperimentalVMOptions"
}

if ($ComponentUid -eq "net.minecraftforge") {
    $profileJson.jvmArgs += "-Dfml.ignorePatchDiscrepancies=true", "-Dfml.ignoreInvalidMinecraftCertificates=true"
}

if ($profileJson."+jvmArgs") {
    $profileJson.jvmArgs += $profileJson."+jvmArgs"
    $profileJson.Remove("+jvmArgs")
}

if ($profileJson.mainClass -eq "io.github.zekerzhayard.forgewrapper.installer.Main") {
    Write-Debug "Running forge 1.14+ installer"

    if ($minecraftVersion -eq "1.16.5") {
        $meta.mavenFiles[0].downloads.artifact.url = "https://github.com/RetroForge/MinecraftForge/releases/download/36.2.41-1.16.5-patched1/forge-1.16.5-36.2.41-installer.jar"

        $forgeLauncher = Get-ChildItem libraries -Recurse -Filter "forge-1.16.5-*-launcher.jar"

        Invoke-RestMethod "https://github.com/RetroForge/MinecraftForge/releases/download/36.2.41-1.16.5-patched1/forge-1.16.5-36.2.41-launcher.jar" -OutFile $forgeLauncher

        $profileJson.minJavaVersion = 17
        $profileJson.recommendJavaVersion = 17
    }
    
    $installerLibPaths = $meta.mavenFiles | ForEach-Object { Get-Library $_ }
    
    $versionJson = Get-ZipEntry $installerLibPaths[0] -Include version.json | Get-ZipEntryContent | ConvertFrom-Json

    $profileJson.clientArgs = $versionJson.arguments.game
    
    $wrapper = "ForgeWrapper.jar"
    Invoke-RestMethod "https://github.com/zznty/ForgeWrapper/releases/latest/download/$wrapper" -OutFile $wrapper

    $clientPath = Get-ChildItem libraries -Recurse -Filter "minecraft-*-client.jar"
    
    $classPath = $profileJson.classPath + $installerLibPaths

    $classPathSeparator = $IsWindows ? ";" : ":"
    
    java "-Dforgewrapper.librariesDir=libraries" "-Dforgewrapper.installer=$($installerLibPaths[0])" "-Dforgewrapper.minecraft=$clientPath" -cp "$wrapper$classPathSeparator$($classPath -join $classPathSeparator)" "io.github.zekerzhayard.forgewrapper.installer.Main" ($profileJson.clientArgs -join " ")

    if ($LastExitCode -ne 0) {
        exit $LastExitCode
    }
    
    Remove-Item $wrapper -Force
}

if (!$SkipGravitTweaks) {
    $profileJson.classPath = $profileJson.classPath | ForEach-Object { 
        $versionPattern = [regex]::Escape(($_ | Split-Path | Split-Path -Leaf))
        [PSCustomObject]@{
            Path     = $_;
            Name     = $_ | Split-Path | Split-Path -Parent;
            Artifact = $_ | Split-Path -LeafBase | ForEach-Object { $_ -replace ".*-$versionPattern-?", "" }
        } 
    } | Sort-Object -Property Name, Artifact -Unique | ForEach-Object { $_.Path }

    Write-Debug "Running GravitTweaks"
    . $PSScriptRoot\tweakGravitProfile.ps1 $profileJson
}

$profileJson | ConvertTo-Json | Out-File $profileJsonPath

Write-Host "Installed $($meta.name) - $($meta.version)"