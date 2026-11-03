function Get-JLPackFolder {
    <#
    .SYNOPSIS
        The pack folders of a packs repository: its subfolders that have a maester-pack.json.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Repo)

    Get-ChildItem -LiteralPath $Repo -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'maester-pack.json') }
}
