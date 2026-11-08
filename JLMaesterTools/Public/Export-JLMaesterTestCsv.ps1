function Export-JLMaesterTestCsv {
    <#
    .SYNOPSIS
        Writes a CSV for New-JLMaesterTest -Path from the policies in the tenant: one row per setting and per child
        setting, every column filled except Recommendation and Severity. Read-only in the tenant.

    .DESCRIPTION
        Reads the settings catalog policies, device configuration profiles (Device Restrictions, Device Features, ...)
        and compliance policies whose name matches -PolicyName and writes one row for each test a benchmark might number:

        - a setting without children: one row, its value in Expected and ValueDisplayName;
        - a setting with children: a row for the setting alone (NoChildren true) and a row for each child, picked with
          ChildSettingDefinitionId, its value in ChildExpected and ChildValueDisplayName. When the benchmark numbers
          the setting and its children as one recommendation, delete the child rows and clear NoChildren;
        - a list (such as a user right's accounts or a deny list of setup classes): its values in Expected (separated
          by ';') or ChildExpected (separated by '|') with the operator in, so every configured value must be one of
          them. Change it to contains when the benchmark says the list must include them;
        - a property of a configuration profile or compliance policy that is configured: one row with Source, ODataType,
          Property and CategoryPath instead of FromPolicy and SettingDefinitionId. A property set to false counts as
          not configured, as in the pack helper, and 0 as a value. A compliance policy's actions for noncompliance
          get a row each, with the grace period in hours.

        Needs a Microsoft Graph connection (Connect-Maester or Connect-MgGraph) with
        DeviceManagementConfiguration.Read.All.
    .PARAMETER PolicyName
        The policy name, or a wildcard such as 'W11_D_CISBL_*'. Written to each row's FromPolicy.
    .PARAMETER Path
        The CSV to write. An existing file is replaced.
    .PARAMETER Pack
        Leave out the settings that already have a test in this pack: a child named in a test, a setting whose test
        checks it alone or with every child the policy configures, and a property tested on that policy type.
    .EXAMPLE
        Export-JLMaesterTestCsv -PolicyName 'W11_D_CISBL_*' -Pack cis-win11-intune-bl -Path .\bl.csv

        Writes bl.csv with a row for every setting of the BitLocker policies that the pack does not test yet.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $PolicyName,
        [Parameter(Mandatory)] [string] $Path,
        [string] $Pack,
        [string] $RepoPath = (Get-Location).Path
    )

    $ErrorActionPreference = 'Stop'
    # Trailing spaces ('Backup Directory ') and form-field colons ('Protocol to use for outgoing RPC connections:')
    # are left out, as New-JLMaesterTest does.
    $bare = { param($Text) ([string]$Text -replace ':\s*$', '').Trim() }

    # What the pack already tests
    $tested = @{}
    $testedProperties = @{}
    if ($Pack) {
        $info = Resolve-JLPack -Repo (Resolve-JLPacksRepo -RepoPath $RepoPath) -Pack $Pack
        foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $info.Path 'tests') -Filter 'Test.*.ps1')) {
            $text = Get-Content -LiteralPath $file.FullName -Raw
            $property = [regex]::Match($text, "(?m)^\s*\[string\]\s*\`$Property\s*=\s*'((?:[^']|'')*)'").Groups[1].Value
            if ($property) {
                $policyType = [regex]::Match($text, "(?m)^\s*\[string\]\s*\`$ODataType\s*=\s*'((?:[^']|'')*)'").Groups[1].Value
                $testedProperties["$policyType|$property"] = $true
                continue
            }
            # One setting ([string]), or several that one test checks each on its own ([string[]]).
            $settingLine = [regex]::Match($text, "(?m)^\s*\[string(\[\])?\]\s*\`$SettingDefinitionId\s*=\s*(.+)$").Groups[2].Value
            $settings = @([regex]::Matches($settingLine, "'((?:[^']|'')*)'") | ForEach-Object { $_.Groups[1].Value.Replace("''", "'") } | Where-Object { $_ })
            if (-not $settings.Count) { continue }
            $childLine = [regex]::Match($text, "(?m)^\s*\[string\[\]\]\s*\`$ChildSettingDefinitionId\s*=\s*(.+)$").Groups[1].Value
            $children = @([regex]::Matches($childLine, "'([^']*)'") | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ })
            foreach ($setting in $settings) {
                if (-not $tested.ContainsKey($setting)) { $tested[$setting] = [System.Collections.Generic.List[object]]::new() }
                $tested[$setting].Add($children)
            }
        }
    }

    # The settings and their children
    # Find-JLIntuneSetting warns when no settings catalog policy has the name, but the policies may be of the other kinds.
    $found = @(Find-JLIntuneSetting -PolicyName $PolicyName -WarningAction SilentlyContinue)
    $profileSettings = @(Get-JLIntuneProfileSetting -PolicyName $PolicyName)
    if ($found.Count -eq 0 -and $profileSettings.Count -eq 0) { throw "No setting found in the policies named like '$PolicyName'." }

    $rows = [System.Collections.Generic.List[object]]::new()
    $seen = @{}
    $columns = 'Recommendation', 'Severity', 'FromPolicy', 'Source', 'ODataType', 'Property', 'CategoryPath', 'SettingDefinitionId', 'SettingDisplayName', 'Operator', 'Expected', 'ValueDisplayName', 'NoChildren',
    'ChildSettingDefinitionId', 'ChildDisplayName', 'ChildOperator', 'ChildExpected', 'ChildValueDisplayName'
    $newRow = {
        $row = [ordered]@{}
        foreach ($c in $columns) { $row[$c] = '' }
        $row.FromPolicy = $PolicyName
        $row
    }
    $copy = {
        param($Row)
        $new = [ordered]@{}
        foreach ($key in $Row.Keys) { $new[$key] = $Row[$key] }
        $new
    }
    $valueOf = {
        param($Setting)
        $values = @($Setting.Value | Where-Object { $_ -ne '' } | Select-Object -Unique)
        $labels = @($values | ForEach-Object {
                $v = $_
                $option = $Setting.Options | Where-Object ItemId -EQ $v | Select-Object -First 1
                if ($option) { $option.DisplayName } else { $v }
            })
        [pscustomobject]@{ Values = $values; Labels = $labels }
    }

    # Put in the order the policy lists them.
    $inOrder = {
        param($Items, $Property)
        $order = [System.Collections.Generic.List[string]]::new()
        $map = @{}
        foreach ($item in @($Items)) {
            $k = [string]$item.$Property
            if (-not $map.ContainsKey($k)) { $map[$k] = [System.Collections.Generic.List[object]]::new(); $order.Add($k) }
            $map[$k].Add($item)
        }
        foreach ($k in $order) { [pscustomobject]@{ Name = $k; Group = $map[$k].ToArray() } }
    }

    foreach ($policyGroup in @(& $inOrder $found PolicyId)) {
        $settings = @($policyGroup.Group)
        $byId = @{}
        foreach ($s in $settings) { if (-not $byId.ContainsKey($s.SettingDefinitionId)) { $byId[$s.SettingDefinitionId] = $s } }
        # The nearest parent with a value: a group setting (such as the entries of Hardened UNC Paths) has none,
        # so its entries belong to the setting above it, or stand alone at the top.
        $ownerOf = {
            param($Setting)
            $parent = $Setting.ParentSettingDefinitionId
            for ($depth = 0; $parent -and $depth -lt 10; $depth++) {
                if ($byId.ContainsKey($parent) -and @($byId[$parent].Value).Count) { return $parent }
                $parent = if ($byId.ContainsKey($parent)) { $byId[$parent].ParentSettingDefinitionId } else { '' }
            }
            ''
        }
        $valued = @($settings | Where-Object { @($_.Value).Count })
        $owners = @{}
        foreach ($s in $valued) { $owners[$s.SettingDefinitionId] = & $ownerOf $s }

        foreach ($top in @(& $inOrder @($valued | Where-Object { -not $owners[$_.SettingDefinitionId] }) SettingDefinitionId)) {
            $setting = $top.Group[0]
            $id = $setting.SettingDefinitionId
            if ($seen.ContainsKey($id)) { continue }
            $seen[$id] = $true
            # Every entry of a list child (one row per entry of a group collection) is one child with all its values.
            $childGroups = @(& $inOrder @($valued | Where-Object { $owners[$_.SettingDefinitionId] -eq $id }) SettingDefinitionId)
            $childIds = @($childGroups | ForEach-Object Name)

            # A test of the setting alone, or with every child the policy configures, covers the setting; a test that
            # names a child covers that child.
            $done = @()
            if ($tested.ContainsKey($id)) { $done = $tested[$id].ToArray() }
            $settingTested = $false
            $childTested = @{}
            foreach ($list in $done) {
                $names = @($list)
                if ($names.Count -eq 0) { $settingTested = $true }
                elseif ($childIds.Count -and @($childIds | Where-Object { $_ -notin $names }).Count -eq 0) { $settingTested = $true }
                foreach ($c in $names) { $childTested[$c] = $true }
            }

            $value = & $valueOf $setting
            $base = & $newRow
            $base.SettingDefinitionId = $id
            $base.SettingDisplayName = & $bare $setting.DisplayName
            $base.Expected = $value.Values -join ';'
            $base.ValueDisplayName = $value.Labels -join ', '
            if ($value.Values.Count -gt 1) { $base.Operator = 'in' }

            if (-not $settingTested) {
                $row = & $copy $base
                if ($childIds.Count) { $row.NoChildren = 'true' }
                $rows.Add([pscustomobject]$row)
            }
            foreach ($group in $childGroups) {
                if ($childTested.ContainsKey($group.Name) -or $settingTested) { continue }
                $child = $group.Group[0]
                $merged = [pscustomobject]@{ Value = @($group.Group | ForEach-Object { $_.Value }); Options = $child.Options }
                $childValue = & $valueOf $merged
                $row = & $copy $base
                $row.ChildSettingDefinitionId = $group.Name
                $row.ChildDisplayName = & $bare $child.DisplayName
                $row.ChildExpected = $childValue.Values -join '|'
                $row.ChildValueDisplayName = $childValue.Labels -join ', '
                if ($childValue.Values.Count -gt 1) { $row.ChildOperator = 'in' }
                $rows.Add([pscustomobject]$row)
            }
        }
    }

    # Configuration profiles and compliance policies: a property of a policy type is written once, like a setting.
    foreach ($setting in $profileSettings) {
        $key = "$($setting.ODataType)|$($setting.Property)"
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        if ($testedProperties.ContainsKey($key)) { continue }
        $row = & $newRow
        $row.FromPolicy = ''
        $row.Source = $setting.Source
        $row.ODataType = $setting.ODataType
        $row.Property = $setting.Property
        $row.CategoryPath = $setting.CategoryPath
        $row.SettingDisplayName = $setting.Property
        $row.Expected = $setting.Value -join ';'
        $row.ValueDisplayName = $setting.ValueDisplayName
        if (@($setting.Value).Count -gt 1) { $row.Operator = 'in' }
        $rows.Add([pscustomobject]$row)
    }

    if ($PSCmdlet.ShouldProcess($Path, "Write $($rows.Count) row(s)")) {
        if ($rows.Count) { $rows | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding utf8 }
        else { Set-Content -LiteralPath $Path -Value ('"' + ($columns -join '","') + '"') -Encoding utf8 }
    }
    [pscustomobject]@{ Path = $Path; Rows = $rows.Count; Settings = $seen.Count }
}
