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

Export-ModuleMember -Function Get-JarManifest