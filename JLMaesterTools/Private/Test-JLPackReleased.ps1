function Test-JLPackReleased {
    <#
    .SYNOPSIS
        Whether a pack version has been released: the git tag <folder>-v<version> exists in the repository. Run
        'git fetch --tags' first; releases are tagged by the CI workflow. Without git or a repository, $false.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)] [string] $Repo,
        [Parameter(Mandatory)] [string] $Folder,
        [Parameter(Mandatory)] [string] $Version
    )

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $false }
    $tag = & git -C $Repo tag --list "$Folder-v$Version" 2>$null
    $global:LASTEXITCODE = 0
    [bool]($tag | Where-Object { $_ })
}
