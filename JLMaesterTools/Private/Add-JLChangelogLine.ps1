function Add-JLChangelogLine {
    <#
    .SYNOPSIS
        Adds a line to the '## <folder> <version>' section of CHANGELOG.md, creating the section under the title when it
        does not exist yet. -Intro is the section's first paragraph when the section is new.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Folder,
        [Parameter(Mandatory)] [string] $Version,
        [string] $Line,
        [string] $Intro
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($l in ([System.IO.File]::ReadAllText($Path) -replace "`r`n", "`n").TrimEnd("`n").Split("`n")) { $lines.Add($l) }
    $heading = "## $Folder $Version"
    $start = $lines.IndexOf($heading)

    if ($start -lt 0) {
        $title = 0
        while ($title -lt $lines.Count -and -not $lines[$title].StartsWith('# ')) { $title++ }
        if ($title -ge $lines.Count) { throw "$Path has no '# ' title line." }
        $section = [System.Collections.Generic.List[string]]::new()
        $section.AddRange([string[]]@('', $heading, ''))
        if ($Intro) { $section.Add($Intro) }
        if ($Line) { if ($Intro) { $section.Add('') }; $section.Add($Line) }
        $lines.InsertRange($title + 1, $section)
    } elseif ($Line) {
        $end = $start + 1
        while ($end -lt $lines.Count -and -not $lines[$end].StartsWith('## ')) { $end++ }
        $last = $end - 1
        while ($last -gt $start -and -not $lines[$last].Trim()) { $last-- }
        $insert = @($Line)
        if (-not $lines[$last].StartsWith('- ')) { $insert = @('', $Line) }
        $lines.InsertRange($last + 1, [string[]]$insert)
    }
    Write-JLTextFile -Path $Path -Text (($lines -join "`n") -replace "\n{3,}", "`n`n")
}
