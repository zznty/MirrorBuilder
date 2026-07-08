function Get-JarManifest {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$JarPath
    )

    $manifestContent = Get-ZipEntry $JarPath -Include "META-INF/MANIFEST.MF" | Get-ZipEntryContent

    $lines = $manifestContent -split [Environment]::NewLine

    $manifest = @{}
    $currentKey = $null

    foreach ($line in $lines) {
        if ($line -match '^(\S.*?):\s*(.*)$') {
            $key = $matches[1]
            $value = $matches[2].Trim()

            $manifest[$key] += $value
            $currentKey = $key
        }
        elseif ($line -match '^\s+(.*)$' -and $null -ne $currentKey) {
            $manifest[$currentKey] += $matches[1].Trim()
        }
    }

    return $manifest
}

function Get-UpstreamComponent {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ComponentUid
    )

    Invoke-RestMethod "https://github.com/PrismLauncher/meta-launcher/archive/refs/heads/master.zip" -OutFile "temp.zip"

    Get-ZipEntry "temp.zip" -Include "meta-launcher-master/$ComponentUid*" | Expand-ZipEntry

    Get-ChildItem -Path "meta-launcher-master" -Directory | Move-Item -Destination "." -Force

    Remove-Item -Path "meta-launcher-master","temp.zip" -Recurse -Force
}

function EmptyToNull {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
        $Value
    )
    process {
        if ($Value) { $Value } else { $null }
    }
}

function NormalizeTimestamp {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
        $Value
    )
    process {
        if (-not $Value) { return $null }
        try {
            $dt = [DateTime]::Parse($Value, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal)
            return $dt.ToString('yyyy-MM-ddTHH:mm:ssK')
        } catch {
            return $null
        }
    }
}

Export-ModuleMember -Function Get-JarManifest,Get-UpstreamComponent,EmptyToNull,NormalizeTimestamp
