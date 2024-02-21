param (
    # Component UID to install
    [Parameter(Mandatory = $true)]
    [string]
    $ComponentUid,

    # Component Version to install
    [Parameter(Mandatory = $true)]
    [string]
    $CompoentVersion,

    # Meta URL
    [Parameter()]
    [string]
    $MetaUrl = "https://meta.prismlauncher.org/v1",

    # Determines if GravitTweaks should be run
    [switch]
    $SkipGravitTweaks
)

$ErrorActionPreference = "Stop"
$DebugPreference = 'Continue'

$meta = Invoke-RestMethod -Uri "$MetaUrl/$ComponentUid/$CompoentVersion.json"

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
    
    $requiredComponentVersion = $requiredComponent.suggests ?? $requiredComponent.equals
    
    if ($null -eq $requiredComponentVersion) {
        Write-Error "Required component $($requiredComponent.uid) does not have a version to install nor currently installed"
        exit 1
    }
    
    pwsh $PSCommandPath -ComponentUid $requiredComponent.uid -CompoentVersion $requiredComponentVersion -SkipGravitTweaks
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

    if (!$library.url -and !$library.downloads.artifact.url) {
        $library | Add-Member "url" "https://libraries.minecraft.net/"
    }

    $url = $library.downloads.artifact.url ?? "$($library.url)$filePath"

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

        $dir = "natives/$($parts[0] -replace "windows", "mustdie")/$($parts.Length -gt 1 ? $parts[1] : "x86-64")"

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

$componentManifest = [PSCustomObject]@{
    uid     = $ComponentUid;
    version = $CompoentVersion
}

$profileJson."+components" += @($componentManifest)

if ($null -eq $meta.mainClass) {
    $profileJson | ConvertTo-Json | Out-File $profileJsonPath
    exit
}

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

$profileJson.updateVerify = "libraries", "mods", "natives"

$profileJson.clientArgs = $meta.minecraftArguments -split " "
if ($meta."+tweakers") {
    foreach ($tweaker in $meta."+tweakers") {
        $profileJson.clientArgs += "--tweakClass", $tweaker
    }
}

$profileJson.jvmArgs = @("-XX:+DisableAttachMechanism")

[version]$minecraftVersion = $profileJson.version

if ($minecraftVersion -le [version]"1.12.2") {
    $profileJson.jvmArgs += "-XX:+UseConcMarkSweepGC", "-XX:+CMSIncrementalMode"
}
elseif ($minecraftVersion -le [version]"1.18") {
    $profileJson.jvmArgs += "-XX:+UseG1GC", "-XX:+UnlockExperimentalVMOptions"
}

if ($ComponentUid -eq "net.minecraftforge") {
    $profileJson.jvmArgs += "-Dfml.ignorePatchDiscrepancies=true", "-Dfml.ignoreInvalidMinecraftCertificates=true"
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
    $classPath = Get-ChildItem libraries -Recurse -Filter "*.jar"
    
    java "-Dforgewrapper.librariesDir=libraries" "-Dforgewrapper.installer=$($installerLibPaths[0])" "-Dforgewrapper.minecraft=$clientPath" -cp "$wrapper;$($classPath -join ";")" "io.github.zekerzhayard.forgewrapper.installer.Main" ($profileJson.clientArgs -join " ")
    
    Remove-Item $wrapper -Force
}

if (!$SkipGravitTweaks) {
    $profileJson.classPath = $profileJson.classPath | ForEach-Object { [PSCustomObject]@{
        Path = $_;
        Name = $_ | Split-Path | Split-Path -Parent
    } } | Sort-Object -Property Name -Unique | ForEach-Object {$_.Path}

    Write-Debug "Running GravitTweaks"
    . $PSScriptRoot\tweakGravitProfile.ps1 $profileJson
}

$profileJson | ConvertTo-Json | Out-File $profileJsonPath

Write-Host "Installed $($meta.name) - $($meta.version)"