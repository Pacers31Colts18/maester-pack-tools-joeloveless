function Save-JLFileState {
    <#
    .SYNOPSIS
        Records the content of files (or that they do not exist) so Restore-JLFileState can undo a failed change.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param([Parameter(Mandatory)] [string[]] $Path)

    $state = [ordered]@{}
    foreach ($p in $Path) {
        $state[$p] = if (Test-Path -LiteralPath $p -PathType Leaf) { [System.IO.File]::ReadAllBytes($p) } else { $null }
    }
    $state
}
