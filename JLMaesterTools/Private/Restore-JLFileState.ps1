function Restore-JLFileState {
    <#
    .SYNOPSIS
        Puts files back as Save-JLFileState recorded them: rewrites changed ones and removes ones that did not exist.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [System.Collections.Specialized.OrderedDictionary] $State)

    foreach ($p in $State.Keys) {
        if ($null -eq $State[$p]) { if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force } }
        else { [System.IO.File]::WriteAllBytes($p, $State[$p]) }
    }
}
