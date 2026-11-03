function Set-JLPackVersion {
    <#
    .SYNOPSIS
        Sets the top-level Version of a maester-pack.json in place, leaving the rest of the file as it is.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $ManifestPath,
        [Parameter(Mandatory)] [ValidatePattern('^\d+\.\d+\.\d+$')] [string] $Version
    )

    $text = [System.IO.File]::ReadAllText($ManifestPath)
    $pattern = '(?m)^(  "Version":\s*")[^"]*(")'
    if (-not [regex]::IsMatch($text, $pattern)) { throw "$ManifestPath has no top-level Version line." }
    if ($PSCmdlet.ShouldProcess($ManifestPath, "Set Version to $Version")) {
        Write-JLTextFile -Path $ManifestPath -Text ([regex]::new($pattern).Replace($text, "`${1}$Version`${2}", 1))
    }
}
