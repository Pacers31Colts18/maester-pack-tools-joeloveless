function Add-JLMarkdownTableRow {
    <#
    .SYNOPSIS
        Adds a row to the markdown table that starts with -Header in a file, optionally keeping the rows sorted.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        # The table's header line, exactly as in the file, such as '| ID | Recommendation # | Title | Severity |'.
        [Parameter(Mandatory)] [string] $Header,
        [Parameter(Mandatory)] [string] $Row,
        # Returns the sort key of a row line; rows stay in file order when omitted.
        [scriptblock] $SortKey
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in ([System.IO.File]::ReadAllText($Path) -replace "`r`n", "`n").TrimEnd("`n").Split("`n")) { $lines.Add($line) }
    $headerIndex = $lines.IndexOf($Header)
    if ($headerIndex -lt 0) { throw "$Path has no table with the header line '$Header'." }
    $first = $headerIndex + 2
    $end = $first
    while ($end -lt $lines.Count -and $lines[$end].StartsWith('|')) { $end++ }

    $rows = @(if ($end -gt $first) { $lines.GetRange($first, $end - $first) }) + $Row
    if ($SortKey) { $rows = @($rows | Sort-Object -Property @{ Expression = $SortKey }) }
    $lines.RemoveRange($first, $end - $first)
    $lines.InsertRange($first, [string[]]$rows)
    Write-JLTextFile -Path $Path -Text ($lines -join "`n")
}
