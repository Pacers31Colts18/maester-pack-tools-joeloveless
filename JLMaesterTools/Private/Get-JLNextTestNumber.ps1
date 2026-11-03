function Get-JLNextTestNumber {
    <#
    .SYNOPSIS
        The next free test number of a pack: one more than the highest Test.MP.<Code>.<number>.ps1 in its tests folder,
        or 1 when there is none.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)] [string] $TestsDir,
        [Parameter(Mandatory)] [string] $Code
    )

    $pattern = '^Test\.MP\.' + [regex]::Escape($Code) + '\.(\d+)\.ps1$'
    $highest = 0
    foreach ($file in @(Get-ChildItem -LiteralPath $TestsDir -Filter 'Test.*.ps1' -File -ErrorAction SilentlyContinue)) {
        if ($file.Name -match $pattern -and [int]$Matches[1] -gt $highest) { $highest = [int]$Matches[1] }
    }
    $highest + 1
}
