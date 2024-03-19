function Invoke-GitGradleBuild {
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

    $patchUrl = [Uri]::IsWellFormedUriString($patchUrl, [UriKind]::Absolute) ? $patchUrl : "$MirrorUrl/$patchUrl"
    
    Invoke-RestMethod $patchUrl | git -C "$buildPath" apply -3 | Out-Null

    if (Test-Path "$buildPath/build.gradle") {
        (Get-Content "$buildPath/build.gradle") | ForEach-Object { $_ -replace "fromTag .*$", "" } | Set-Content "$buildPath/build.gradle"
    }
    
    $gradle = "$buildPath/gradlew"
    if ($IsWindows) {
        $gradle += ".bat"
    }
    
    Write-Debug "Running gradle build"
    
    $prevPwd = $PWD

    Set-Location $buildPath

    if (!$IsWindows) {
        chmod +x $gradle
    }
    
    & $gradle build

    Set-Location $prevPwd

    if ($LastExitCode -ne 0) {
        throw "Gradle build failed"
    }
    
    $jarPath = Get-ChildItem (Join-Path $buildPath -ChildPath "build/libs/") -Exclude "*-sources.jar", "*-javadoc.jar" | Select-Object -First 1
    
    Copy-Item $jarPath -Force -Destination $outputPath
    
    Remove-Item $buildPath -Recurse -Force -ErrorAction Ignore
}

Export-ModuleMember -Function Invoke-GitGradleBuild