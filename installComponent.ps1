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
    $ChildProcess,

    [switch]
    $ServerWrapperProfile
)

$ErrorActionPreference = "Stop"
$DebugPreference = 'Continue'

if ($env:META_URL) {
    $MetaUrl = $env:META_URL
}

if ($MetaUrl.EndsWith(".zip")) {
    Invoke-RestMethod -Uri "$MetaUrl" -OutFile "meta.zip"

    Import-Module PSCompression

    $meta = Get-ZipEntry -Path meta.zip -Include "$ComponentUid/$CompoentVersion.json" | Get-ZipEntryContent | ConvertFrom-Json

    Remove-Item meta.zip
}
elseif ($MMCPatch) {
    $meta = Get-Content "mmc/patches/$ComponentUid.json" | ConvertFrom-Json
}
else {
    $meta = Invoke-RestMethod -Uri "$MetaUrl/$ComponentUid/$CompoentVersion.json"
}

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

    if ($requiredComponent.uid -eq "net.minecraftforge" -and $requiredComponentVersion -match "36.2.\d+") {
        $requiredComponentVersion = "36.2.41"
    }
    
    pwsh $PSCommandPath -ComponentUid $requiredComponent.uid -CompoentVersion $requiredComponentVersion -ChildProcess -SkipGravitTweaks -MMCPatch:$($MMCPatch.IsPresent) -ServerWrapperProfile:$($ServerWrapperProfile.IsPresent)
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
        $library | Add-Member "url" "https://libraries.minecraft.net/" -Force
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
    
    if ($library.name -match "^.*:natives-(macos|linux|windows)(-(arm32|arm64|x86))?$" -or $library.name -match "^[\w\.]*:([\w\.(?!natives)]*-){1,2}natives-(macos|linux|windows)(-(arm32|arm64|x86))?:(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?:?[\w\.]*$") {
        Invoke-RestMethod -Uri $url -OutFile temp

        Get-ZipEntry temp -Exclude "META-INF/*" -Type Archive | ForEach-Object { 
            $path = "natives/$($_.RelativePath -replace "windows", "mustdie" -replace "osx", "macos" -replace "x64", "x86-64")"
            $path = $path -split "(natives/(macos|linux|mustdie)/(arm32|arm64|x86|x86-64))/"
            $path = Join-Path $path[1] -ChildPath (Split-Path -Leaf $path[-1])

            New-Item -ItemType Directory ($path | Split-Path) -Force | Out-Null
            $_  | Get-ZipEntryContent -AsByteStream | Set-Content -Path $path -AsByteStream
        }

        Remove-Item temp

        return $null
    }

    New-Item -Type Directory "libraries/$($dirArray -join "/")" -Force | Out-Null
    
    foreach ($url in $library.'MMC-hint' -eq "maven" ? ($meta.maven | ForEach-Object { "$_/$filePath" }) : @($url)) {
        try {
            if ($library.downloads.artifact.archivePath) {
                Invoke-RestMethod -Uri $url -OutFile "$OutFile.fat"

                Get-ZipEntry "$OutFile.fat" -Include $library.downloads.artifact.archivePath | Get-ZipEntryContent -AsByteStream | Set-Content -Path $OutFile -AsByteStream
            }
            else {
                Invoke-RestMethod -Uri $url -OutFile $OutFile
            }
        }
        catch {
            Write-Debug "Failed to download $($library.name) - $url"
        }
    }

    if (!(Test-Path $OutFile)) {
        throw "Failed to download $($library.name) - $url"
    }
    
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

function Get-ProfileComponentVersion {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]
        $ComponentUid
    )
    
    $profileJson."+components" | Where-Object { $_.uid -eq $ComponentUid } | Select-Object -ExpandProperty version
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
$profileJson.classLoaderConfig = $ServerWrapperProfile ? "MODULE" : "LAUNCHER" # default, module means launcher for server wrapper

if (!$ServerWrapperProfile) {
    $profileJson.title = "$($meta.name) $($meta.version)"
    $profileJson.uuid = "$(New-Guid)"
    if ($ComponentUid -eq "net.minecraft") {
        $profileJson.version = $meta.version
        $profileJson.assetIndex = $meta.version
        $profileJson.dir = $meta.version
    }
    $profileJson.assetDir = "assets"
    $profileJson.info = "Server description"
    $profileJson.update = @("servers.dat")
    $profileJson.updateVerify = "libraries", "mods", "natives"
}
else {
    $profileJson.address = "ws://localhost:9274/api"
    $profileJson.serverName = "$($meta.name)-$($meta.version)"
    $profileJson.nativesDir = "natives"
    $profileJson.autoloadLibraries = $false
}

$profileJson.mainClass = $meta.mainClass

if ($meta.compatibleJavaMajors) {
    $profileJson.minJavaVersion = $meta.compatibleJavaMajors[0]
    $profileJson.recommendJavaVersion = $meta.compatibleJavaMajors[-1]
    $profileJson.maxJavaVersion = 999 # default
}

$argsPropertyName = $ServerWrapperProfile ? "args" : "clientArgs"

$profileJson.$argsPropertyName = $meta.minecraftArguments -split " "
if ($meta."+tweakers") {
    foreach ($tweaker in $meta."+tweakers") {
        $profileJson.$argsPropertyName += "--tweakClass", $tweaker
    }
}

if ($ChildProcess -and $profileJson.mainClass -ne "io.github.zekerzhayard.forgewrapper.installer.Main") {
    $profileJson | ConvertTo-Json -Depth 100 | Out-File $profileJsonPath
    Write-Host "Installed $($meta.name) - $($meta.version)"
    exit
}

$profileJson.jvmArgs = $ServerWrapperProfile ? "-Xms1G", "-Xmx1G" : @("-XX:+DisableAttachMechanism")

[version]$minecraftVersion = Get-ProfileComponentVersion "net.minecraft"

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

        if (!$forgeLauncher) {
            $forgeLauncher = "libraries/net/minecraftforge/forge/1.16.5-36.2.41/forge-1.16.5-36.2.41-launcher.jar"
            $profileJson.classPath += $forgeLauncher
        }

        Invoke-RestMethod "https://github.com/RetroForge/MinecraftForge/releases/download/36.2.41-1.16.5-patched1/forge-1.16.5-36.2.41-launcher.jar" -OutFile $forgeLauncher

        $profileJson.minJavaVersion = 17
        $profileJson.recommendJavaVersion = 17
    }
    
    $installerLibPaths = $meta.mavenFiles | ForEach-Object { Get-Library $_ }
    
    $versionJson = Get-ZipEntry $installerLibPaths[0] -Include version.json | Get-ZipEntryContent | ConvertFrom-Json

    $profileJson.$argsPropertyName = $ServerWrapperProfile ? $meta.minecraftArguments : $versionJson.arguments.game

    $clientPath = Get-ChildItem libraries -Recurse -Filter ($ServerWrapperProfile ? "server-$minecraftVersion.jar" : "minecraft-*-client.jar") | Resolve-Path -Relative
    $clientPath = $clientPath -replace "\.[\\/]", "" -replace "\\", "/"

    if (Test-Path "$clientPath.fat") {
        $clientPath = "$clientPath.fat"
    }
    
    $classPath = $profileJson.classPath + $installerLibPaths

    $classPathSeparator = $IsWindows ? ";" : ":"

    $wrapperJvmArgs = "-Dforgewrapper.librariesDir=libraries", "-Dforgewrapper.installer=$($installerLibPaths[0])", "-Dforgewrapper.minecraft=$clientPath"
    
    $wrapper = "ForgeWrapper.jar"
    Invoke-RestMethod "https://github.com/zznty/ForgeWrapper/releases/latest/download/$wrapper" -OutFile $wrapper

    java $wrapperJvmArgs -cp "$wrapper$classPathSeparator$($classPath -join $classPathSeparator)" "io.github.zekerzhayard.forgewrapper.installer.Main" $profileJson.$argsPropertyName --setup

    if ($LastExitCode -ne 0) {
        exit $LastExitCode
    }
    
    Remove-Item $wrapper -Force

    $profileJson.jvmArgs += $wrapperJvmArgs -replace "\.fat", ""

    if ($ServerWrapperProfile) {
        # Cleanup after forge installer

        Remove-Item -Force "run.*" -ErrorAction Ignore
        Remove-Item -Force "user_jvm_args.txt" -ErrorAction Ignore
    }
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

    if ($ServerWrapperProfile) {
        $profileJson.$argsPropertyName += "nogui"
        $profileJson.jvmArgs -join " " | Set-Content jvm_args.txt
        $profileJson.Remove("jvmArgs")

        $profileJson.mainclass = $profileJson.mainClass
        $profileJson.Remove("mainClass")

        $profileJson.classpath = $profileJson.classPath
        $profileJson.Remove("classPath")

        $profileJson.env = "STD"
        $profileJson.oauthExpireTime = 0
        $profileJson.extendedTokens = [PSCustomObject]@{
            checkServer = [PSCustomObject]@{
                token = "your token"
            }
        }
        $profileJson.encodedServerRsaPublicKey = "base64 -w 0 .keys/rsa_id.pub | tr '/+' '_-'"
        $profileJson.encodedServerEcPublicKey = "base64 -w 0 .keys/ecdsa_id.pub | tr '/+' '_-'"
    }
}

$profileJson | ConvertTo-Json -Depth 100 | Out-File $profileJsonPath

if ($ServerWrapperProfile -and !$SkipGravitTweaks) {
    Copy-Item "$PSScriptRoot\templates\start.sh" "."
    Move-Item "profile.json" "ServerWrapperConfig.json"

    Get-ChildItem -Recurse libraries -File -Filter "*.fat" | Remove-Item 
}

Write-Host "Installed $($meta.name) - $($meta.version)"