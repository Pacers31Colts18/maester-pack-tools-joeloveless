function Get-JLRecommendationSortKey {
    <#
    .SYNOPSIS
        A key that sorts recommendation numbers the way a benchmark lists them: 1.2 before 1.10, 2.1 after 1.10.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string] $Recommendation)

    (@($Recommendation -split '\.' | ForEach-Object { if ($_ -match '^\d+$') { $_.PadLeft(6, '0') } else { $_ } })) -join '.'
}
