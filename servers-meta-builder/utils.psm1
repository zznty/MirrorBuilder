function Get-JarManifest {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$JarPath
    )

    # Get MANIFEST.MF content
    $manifestContent = Get-ZipEntry $JarPath -Include "META-INF/MANIFEST.MF" | Get-ZipEntryContent

    # Split the content into lines
    $lines = $manifestContent -split [Environment]::NewLine

    $manifest = @{}
    $currentKey = $null

    foreach ($line in $lines) {
        if ($line -match '^(\S.*?):\s*(.*)$') {
            # Extract key and value
            $key = $matches[1]
            $value = $matches[2].Trim()

            $manifest[$key] += $value
            $currentKey = $key
        }
        elseif ($line -match '^\s+(.*)$' -and $null -ne $currentKey) {
            # If the line starts with space, treat it as a continuation of the previous entry
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
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $Value
    )
    process {
        if ($Value) { $Value } else { $null }
    }
}

function NormalizeTimestamp {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
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
