function Resolve-JLPacksRepo {
    <#
    .SYNOPSIS
        The full path of a packs repository: a folder with shared/helpers, README.md and CHANGELOG.md.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string] $RepoPath)

    $full = (Resolve-Path -LiteralPath $RepoPath -ErrorAction Stop).Path
    foreach ($required in 'shared/helpers', 'README.md', 'CHANGELOG.md') {
        if (-not (Test-Path -LiteralPath (Join-Path $full $required))) {
            throw "$full is not a packs repository: it has no $required. Pass -RepoPath, or run from the repository folder."
        }
    }
    $full
}
