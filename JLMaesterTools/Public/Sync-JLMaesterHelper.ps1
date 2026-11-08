function Sync-JLMaesterHelper {
    <#
    .SYNOPSIS
        Copies shared/helpers/*.ps1 of a packs repository into the helpers folder of every pack, with a header line.
    .DESCRIPTION
        A pack loads into a private module of its own and cannot see another pack's helpers, so every pack ships a
        copy; shared/helpers is the only place to change them. Each helper file must hold exactly one function, named
        after the file. With -Check nothing is written: it fails when any pack's copy differs (CI runs it this way).
    .PARAMETER RepoPath
        The packs repository. Defaults to the current folder.
    .PARAMETER Check
        Only compare; throw when a pack's helpers differ from shared/helpers.
    .EXAMPLE
        Sync-JLMaesterHelper -RepoPath C:\Users\jlove\GitHub\maester-packs-joeloveless
    .EXAMPLE
        Sync-JLMaesterHelper -Check
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string] $RepoPath = (Get-Location).Path,
        [switch] $Check
    )

    $ErrorActionPreference = 'Stop'
    # Progress goes to the information stream, shown unless the caller passes -InformationAction.
    if (-not $PSBoundParameters.ContainsKey('InformationAction')) { $InformationPreference = 'Continue' }
    $repo = Resolve-JLPacksRepo -RepoPath $RepoPath
    $source = Join-Path $repo 'shared/helpers'
    $files = @(Get-ChildItem -LiteralPath $source -Filter '*.ps1' | Sort-Object Name)
    if ($files.Count -eq 0) { throw "No .ps1 files in $source." }
    foreach ($file in $files) {
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$parseErrors)
        if ($parseErrors) { throw "shared/helpers/$($file.Name) does not parse: $($parseErrors[0].Message)" }
        $statements = @($ast.EndBlock.Statements)
        if ($statements.Count -ne 1 -or $statements[0] -isnot [System.Management.Automation.Language.FunctionDefinitionAst] -or $statements[0].Name -ne $file.BaseName) {
            throw "shared/helpers/$($file.Name) must hold exactly one function, named $($file.BaseName)."
        }
    }
    $packs = @(Get-JLPackFolder -Repo $repo)
    if ($packs.Count -eq 0) { throw "No pack folders in $repo." }

    $expected = [ordered]@{}
    foreach ($file in $files) {
        $body = [System.IO.File]::ReadAllText($file.FullName).TrimStart([char]0xFEFF) -replace "`r`n", "`n"
        $expected[$file.Name] = "# Copied from shared/helpers/$($file.Name) by tools/Sync-Helpers.ps1. Do not edit here.`n$body"
    }

    $stale = [System.Collections.Generic.List[string]]::new()
    foreach ($pack in $packs) {
        $target = Join-Path $pack.FullName 'helpers'
        $existing = @(if (Test-Path -LiteralPath $target) { Get-ChildItem -LiteralPath $target -Filter '*.ps1' })
        if ($Check) {
            foreach ($name in $expected.Keys) {
                $path = Join-Path $target $name
                if (-not (Test-Path -LiteralPath $path) -or ([System.IO.File]::ReadAllText($path) -replace "`r`n", "`n") -ne $expected[$name]) { $stale.Add("$($pack.Name)/helpers/$name") }
            }
            foreach ($file in $existing) { if (-not $expected.Contains($file.Name)) { $stale.Add("$($pack.Name)/helpers/$($file.Name) (not in shared/helpers)") } }
            continue
        }
        if (-not $PSCmdlet.ShouldProcess("$($pack.Name)/helpers", "Sync $($expected.Count) helper file(s)")) { continue }
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        foreach ($file in $existing) { if (-not $expected.Contains($file.Name)) { Remove-Item -LiteralPath $file.FullName } }
        foreach ($name in $expected.Keys) { [System.IO.File]::WriteAllText((Join-Path $target $name), $expected[$name], [System.Text.UTF8Encoding]::new($false)) }
        Write-Information "$($pack.Name): $($expected.Count) helper file(s) synced."
    }

    if ($Check) {
        if ($stale.Count -gt 0) { throw "Helpers out of sync; run Sync-JLMaesterHelper:`n - " + ($stale -join "`n - ") }
        Write-Information "Helpers in sync in $($packs.Count) pack(s)."
    }
}
