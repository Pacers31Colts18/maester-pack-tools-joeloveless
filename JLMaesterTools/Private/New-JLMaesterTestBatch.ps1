function New-JLMaesterTestBatch {
    <#
    .SYNOPSIS
        New-JLMaesterTest -Path: one test per CSV row, all or nothing.

    .DESCRIPTION
        Columns are New-JLMaesterTest parameter names (any case); an unknown column stops the run. Empty cells are left
        out. SettingDefinitionId, Expected and the Child* columns take several values separated by ';'. Parameters passed with -Path apply to
        every row (-Defaults); a cell overrides them for its row.

        Every row is drafted first (with its -FromPolicy lookup), and recommendations and function names are checked
        for duplicates within the CSV. Rows are numbered in order from the pack's next free test number. If any row fails, nothing is written and the error lists every failing row.
        Otherwise all rows are written, then Get-MtTest and Test-MtPack run once per pack; if they reject anything, every
        file the run touched is put back.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [hashtable] $Defaults,
        [Parameter(Mandatory)] [string] $RepoPath
    )

    $ErrorActionPreference = 'Stop'
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Path does not exist." }
    $rows = @(Import-Csv -LiteralPath $Path)
    if ($rows.Count -eq 0) { throw "$Path has no rows." }

    # The columns a row may set: New-JLMaesterTest's own parameters, less the ones that steer this run.
    $command = Get-Command New-JLMaesterTest
    $notColumns = @('Path', 'RepoPath', 'DraftOnly', 'SkipPackCheck', 'WhatIf', 'Confirm') +
        [System.Management.Automation.PSCmdlet]::CommonParameters + [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
    $names = @{}
    foreach ($name in $command.Parameters.Keys) { if ($name -notin $notColumns) { $names[$name] = $name } }
    $unknown = @($rows[0].PSObject.Properties.Name | Where-Object { -not $names.ContainsKey($_) })
    if ($unknown.Count) { throw "$Path has column(s) that are not New-JLMaesterTest parameters: $($unknown -join ', '). Columns can be: $(($names.Values | Sort-Object) -join ', ')." }
    $lists = 'SettingDefinitionId', 'Expected', 'ChildSettingDefinitionId', 'ChildExpected', 'ChildDisplayName', 'ChildValueDisplayName', 'ChildOperator'

    # --- Draft every row ----------------------------------------------------------------------------------------------
    # The drafts are not on disk, so each row of a pack gets the next number by hand, in row order.
    $nextNumber = @{}
    # A row without a Recommendation is skipped (such as a setting from Export-JLMaesterTestCsv that the benchmark
    # does not number); the run lists them.
    $skipped = [System.Collections.Generic.List[string]]::new()
    $entries = for ($i = 0; $i -lt $rows.Count; $i++) {
        $params = @{} + $Defaults
        $params.RepoPath = $RepoPath
        foreach ($cell in $rows[$i].PSObject.Properties) {
            $value = [string]$cell.Value
            if (-not $value.Trim()) { continue }
            $name = $names[$cell.Name]
            $params[$name] = if ($name -in $lists) { @(($value -split ';').ForEach({ $_.Trim() }) | Where-Object { $_ }) }
            elseif ($command.Parameters[$name].ParameterType -eq [switch]) { [switch]($value.Trim() -match '^(true|yes|1)$') }
            else { $value.Trim() }
        }
        if (-not $params.Recommendation) {
            $what = @($params.SettingDisplayName, $params.ChildDisplayName | Where-Object { $_ }) -join ': '
            if (-not $what) { $what = @($params.SettingDefinitionId, $params.ChildSettingDefinitionId | Where-Object { $_ }) -join ': ' }
            $skipped.Add("row $($i + 2)$(if ($what) { " ($what)" })")
            continue
        }
        $entry = [pscustomobject]@{ Row = $i + 2; Recommendation = $params.Recommendation; Params = $params; Draft = $null; Error = $null }
        # A Replace row keeps its test's number and Severity, so it needs neither.
        $replace = $params.ContainsKey('Replace') -and $params.Replace
        $missing = @(@('Pack', 'Recommendation') + $(if (-not $replace) { 'Severity' }) | Where-Object { -not $params[$_] })
        if ($missing.Count) { $entry.Error = "missing $($missing -join ', ')" }
        else {
            try {
                if (-not $replace) {
                    if (-not $nextNumber.ContainsKey($params.Pack)) {
                        $info = Resolve-JLPack -Repo (Resolve-JLPacksRepo -RepoPath $RepoPath) -Pack $params.Pack
                        $nextNumber[$params.Pack] = Get-JLNextTestNumber -TestsDir (Join-Path $info.Path 'tests') -Code ([string]$info.Manifest.Code)
                    }
                    $params.Number = $nextNumber[$params.Pack]
                    $nextNumber[$params.Pack] += 1
                }
                $entry.Draft = New-JLMaesterTest @params -DraftOnly -WhatIf:$false -Confirm:$false
            } catch { $entry.Error = $_.Exception.Message }
        }
        $entry
    }
    $entries = @($entries)
    if ($skipped.Count) { Write-Warning "Skipped $($skipped.Count) row(s) without a Recommendation: $($skipped -join '; ')." }
    if ($entries.Count -eq 0) { throw "$Path has no row with a Recommendation." }

    # Two rows of one CSV can't see each other in a draft: the same recommendation, or the same function, in one pack.
    foreach ($group in @($entries | Where-Object Draft | Group-Object { "$($_.Params.Pack)|$($_.Params.Recommendation)" } | Where-Object Count -GT 1)) {
        foreach ($entry in $group.Group) { $entry.Error = "recommendation $($entry.Params.Recommendation) is in rows $(($group.Group.Row) -join ' and ')" }
    }
    foreach ($group in @($entries | Where-Object { $_.Draft -and -not $_.Error } | Group-Object { "$($_.Params.Pack)|$($_.Draft.FunctionName)" } | Where-Object Count -GT 1)) {
        foreach ($entry in $group.Group) { $entry.Error = "$($entry.Draft.FunctionName) is the function of rows $(($group.Group.Row) -join ' and '); pass FunctionName" }
    }
    $failed = @($entries | Where-Object Error)
    if ($failed.Count) {
        $lines = @($failed | ForEach-Object { " - Row $($_.Row)$(if ($_.Recommendation) { " ($($_.Recommendation))" }): $($_.Error)" })
        throw "$($failed.Count) of $($entries.Count) row(s) in $Path failed; nothing was written.`n$($lines -join "`n")"
    }

    $summary = {
        param($Entry, [switch] $WithDrafts)
        $out = [ordered]@{
            Row         = $Entry.Row
            Id          = $Entry.Draft.Id
            Title       = $Entry.Draft.Title
            Area        = $Entry.Draft.Area
            Children    = (@($Entry.Draft.Children) | ForEach-Object { "$($_.DisplayName) = $($_.ValueDisplayName)" }) -join '; '
            Replaces    = $Entry.Draft.Replaces
            PackVersion = $Entry.Draft.PackVersion
        }
        if ($WithDrafts) { $out.Ps1 = $Entry.Draft.Ps1; $out.Markdown = $Entry.Draft.Markdown }
        [pscustomobject]$out
    }
    if (-not $PSCmdlet.ShouldProcess($Path, "Create $($entries.Count) test(s): $(($entries.Draft.Id) -join ', ')")) {
        return $entries | ForEach-Object { & $summary $_ -WithDrafts }
    }

    # --- Write every row, then check each pack once -------------------------------------------------------------------
    $repo = Resolve-JLPacksRepo -RepoPath $RepoPath
    $packs = @{}
    foreach ($pack in @($entries.Params.Pack | Select-Object -Unique)) { $packs[$pack] = Resolve-JLPack -Repo $repo -Pack $pack }
    $paths = @($entries.Draft.Files) + @($packs.Values | ForEach-Object { $_.FrameworkPath, $_.ReadmePath, $_.ManifestPath }) + (Join-Path $repo 'CHANGELOG.md')
    $state = Save-JLFileState -Path @($paths | Select-Object -Unique)
    # Undone in finally, not catch: a stopped run (Ctrl+C) skips catch blocks but still runs finally.
    $done = $false
    try {
        foreach ($entry in $entries) {
            $params = $entry.Params
            $null = New-JLMaesterTest @params -SkipPackCheck -WhatIf:$false -Confirm:$false
        }
        foreach ($pack in $packs.Keys) {
            $info = $packs[$pack]
            $tests = @(Get-MtTest -Path $info.Path)
            foreach ($entry in @($entries | Where-Object { $_.Params.Pack -eq $pack })) {
                $written = @($tests | Where-Object Id -EQ $entry.Draft.Id)
                if ($written.Count -ne 1) { throw "Get-MtTest did not find $($entry.Draft.Id) after writing it." }
                if (-not $written[0].IsValid) { throw "Get-MtTest rejects $($entry.Draft.Id): $(@($written[0].Errors | ForEach-Object { if ($_.Message) { $_.Message } else { "$_" } }) -join '; ')" }
                if ([string]$written[0].Benchmark.Requirement -ne $entry.Params.Recommendation) { throw "$($entry.Draft.Id) does not resolve to requirement $($entry.Params.Recommendation) of $($info.FrameworkKey)." }
            }
            $check = Test-MtPack $info.Path
            if (-not $check.IsValid -or $check.Risk -ne 'Low' -or @($check.Findings).Count) { throw "Test-MtPack rejects $($pack): $(@($check.Errors | ForEach-Object { $_.Message }) -join '; ')" }
        }
        $done = $true
    } catch {
        throw "Nothing was written from $($Path): $($_.Exception.Message)"
    } finally {
        if (-not $done) { Restore-JLFileState -State $state }
    }
    $entries | ForEach-Object { & $summary $_ }
}
