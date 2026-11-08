function New-JLMaesterTest {
    <#
    .SYNOPSIS
        Adds a setting test to a pack: Test.<ID>.ps1 and .md, the framework requirement, the README row, the CHANGELOG
        line and, when the pack's current version is already released, a version bump.
    .DESCRIPTION
        The test ID is MP.<pack Code>.<number>: tests are numbered in the order they are added (001, 002, ...), the
        next free number in the pack. The recommendation is in the test's Control (the framework requirement) and in
        the .md. The .ps1 follows the repository's template: what the test checks in param() with the recommendation's
        values as defaults, the operator as a literal, and a body that calls the shared helper Test-JlIntuneSetting.
        The title is '<setting> is set to <value>' and the function is named after the setting definition id. The .md
        opens with a Description section: -Description, which you write in your own words (never paste benchmark text),
        then '<benchmark>, recommendation <n> (Level <n>).' and what passes; then remediation steps and links.

        With -FromPolicy the setting definition id, display name, category, platform and value are read from a settings
        catalog policy in the connected tenant (Find-JLIntuneSetting); pass -ValueDisplayName to require another option
        than the one that policy sets.

        After writing, Get-MtTest and Test-MtPack must accept the pack; otherwise every change is undone. -WhatIf
        writes nothing and returns both drafts in Ps1 and Markdown, to review before writing.
    .PARAMETER Path
        A CSV file with one test per row; the columns are this command's parameter names (Recommendation, Severity,
        FromPolicy, SettingDisplayName, ValueDisplayName, Area, Description, ...). Empty cells are left out; Expected
        and the Child* columns take several values separated by ';'. Other parameters passed with -Path, such as -Pack,
        apply to every row and a cell overrides them. A row without a Recommendation is skipped and listed in a
        warning (Export-JLMaesterTestCsv writes every setting; fill in the ones to test). All or nothing: every row
        is drafted first, and if any fails nothing is written. Get-MtTest and Test-MtPack then run once; if they
        reject the result, every file is put back. With -WhatIf it returns every draft.
    .PARAMETER Pack
        The pack folder, such as cis-win11-intune-l1.
    .PARAMETER Recommendation
        The recommendation number as the benchmark writes it, such as 1.1 or 18.4.1. It links the test to the
        framework requirement (Control) and is named in the .md's Description section; the test ID is a number.
    .PARAMETER Description
        What the setting does and why it matters, in your own words (markdown). The first paragraph of the .md's
        Description section, before the recommendation line. Optional.
    .PARAMETER SettingDisplayName
        The setting's name as Intune shows it, such as 'Allow Cortana Above Lock'. With -FromPolicy it may be a
        wildcard that picks the setting.
    .PARAMETER Source
        Where the setting lives: settingsCatalog (the default), compliance or deviceConfiguration with -ODataType and
        -Property, or tenantSetting with -Property: the tenant's Compliance policy settings, such as secureByDefault
        and deviceComplianceCheckinThresholdDays, which apply to every device.
    .PARAMETER Property
        The property to check, dots for nested, name[key=value] to keep the items of a list that match. A compliance
        policy's Mark device noncompliant, in hours, is
        scheduledActionsForRule.scheduledActionConfigurations[actionType=block].gracePeriodHours.
    .PARAMETER SettingDefinitionId
        The settings catalog setting definition id. With -FromPolicy, several when one recommendation needs each of
        them, such as the same timer under Desktop Power, Laptop Battery Power and Laptop Power (';' between them in a
        CSV cell): one test that passes only when every one passes on its own, without child settings. Their names and
        categories come from the policy; -SettingDisplayName names them in the title.
    .PARAMETER ValueDisplayName
        The required value's label, such as 'Block'. With -FromPolicy it picks the option by label (of every setting,
        when there are several).
    .PARAMETER Expected
        The required value: the option id for a choice setting (..._0), the value for others. Several for in/notIn.
        With several settings: one value for all of them (such as a match pattern) or one per setting in the same
        order, a setting's values for in, notIn and contains separated by '|'.
    .PARAMETER ChildSettingDefinitionId
        Child settings that must also be set, in the same policy (such as the options under an Administrative
        Templates setting's Enabled). With -FromPolicy, every child the policy configures under the setting is
        checked unless -NoChildren is set; -ChildSettingDefinitionId alone picks which of them, with their values and
        names from the policy. Use that for a parent with several children that the benchmark numbers separately,
        such as Configure RPC connection settings; the title and function then name the parent and the child:
        '<setting>: <child> is set to Enabled: <child value>'; -ChildExpected, -ChildDisplayName and
        -ChildValueDisplayName given with it replace the policy's values and names. Without -FromPolicy, pairs with
        -ChildExpected, -ChildDisplayName and -ChildValueDisplayName, in the same order.
    .PARAMETER ChildExpected
        The value each child setting requires (the option id for a choice setting), compared with -ChildOperator (eq
        when left out).
    .PARAMETER ChildDisplayName
        Each child setting's name as Intune shows it, such as 'Configure MrxSmb10 driver'.
    .PARAMETER ChildValueDisplayName
        Each child's required value label, such as 'Disable driver (recommended)'. Added to the title after the
        setting's value: '<setting> is set to Enabled: Disable driver (recommended)'.
    .PARAMETER ChildOperator
        How each child setting is compared, in the same order as the children: eq when left out. ge for a size 'or
        greater', in for one of several values (separated by '|' in -ChildExpected, as a CSV cell already uses ';'
        between children), exists for any value (no -ChildExpected needed). With -FromPolicy, -ChildDisplayName and
        -ChildValueDisplayName replace the policy's names in the title and .md, such as '32,768 or more'.
    .PARAMETER NoChildren
        With -FromPolicy, check only the setting, not the children the policy configures under it.
    .PARAMETER Replace
        Rewrites the test that already checks -Recommendation, under the same ID: its files, README row and CHANGELOG
        line (the framework requirement stays). -Severity and -Description default to the old test's.
    .PARAMETER Level
        The requirement's level fact, such as L1. Defaults to the framework file's Level, or the level every existing
        requirement shares.
    .PARAMETER Product
        The product the Maester report groups the test under (its Category). Defaults to Product in the pack's
        framework file, such as Intune.
    .PARAMETER Feature
        The feature within the product. Defaults to the framework file's Name without '(Level n)', followed by the
        pack's level, such as CIS Microsoft Intune for Windows 11 Benchmark (L1), so -Feature in Invoke-Maester picks
        one level.
    .PARAMETER Area
        The section the setting is in, such as Above Lock; the report filters on it. Defaults to the setting's own
        Intune category, the last level of its category path (-CategoryPath, or read by -FromPolicy): Sleep Settings
        for Administrative Templates > System > Power Management > Sleep Settings. The .md names the whole path. Pass
        it when the test has no category path (compliance and deviceConfiguration sources).

    .PARAMETER SkipReason
        Writes a test that is always skipped, with this reason, for a recommendation no Intune policy setting can show,
        such as a service set by a script. It needs -SettingDisplayName, -ValueDisplayName and -Area, and takes no
        setting (-FromPolicy, -SettingDefinitionId, -Expected, ...). The test still links to its recommendation, so
        the report lists it as skipped.
    .PARAMETER NoVersionBump
        Do not bump the pack version even when its current version is released.
    .EXAMPLE
        New-JLMaesterTest -Pack cis-win11-intune-l1 -Recommendation 1.1 -Severity High `
            -FromPolicy 'W11_D_CISL1_*' -SettingDisplayName 'Allow Cortana Above Lock' -ValueDisplayName Block `
            -Description 'Cortana should not answer voice requests while the device is locked.' -WhatIf

        Takes Area from the setting's Intune category, Product and Feature from the framework file, then returns both
        drafts without writing.
    .EXAMPLE
        New-JLMaesterTest -Path .\tests.csv -Pack cis-win11-intune-l1 -WhatIf

        Drafts one test per row of tests.csv (columns such as Recommendation, Severity, FromPolicy, SettingDisplayName,
        ValueDisplayName, Area) and writes nothing. Without -WhatIf it writes them all, or none.
    .EXAMPLE
        New-JLMaesterTest -Pack cis-win11-intune-l1 -Recommendation 1.1 -Severity High -Platform windows10 -Area 'Above Lock' `
            -SettingDefinitionId device_vendor_msft_policy_config_abovelock_allowcortanaabovelock `
            -Expected device_vendor_msft_policy_config_abovelock_allowcortanaabovelock_0 `
            -SettingDisplayName 'Allow Cortana Above Lock' -ValueDisplayName Block -CategoryPath 'Above Lock' `
            -Description 'Cortana should not answer voice requests while the device is locked.'
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Single')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Csv')] [string] $Path,
        [Parameter(Mandatory, ParameterSetName = 'Single')] [Parameter(ParameterSetName = 'Csv')] [string] $Pack,
        [Parameter(Mandatory, ParameterSetName = 'Single')] [ValidatePattern('^[A-Za-z0-9]+([.-][A-Za-z0-9]+)*$')] [string] $Recommendation,
        # Required, except with -Replace (the old test's); checked in the body so -Replace can leave it out.
        [ValidateSet('Critical', 'High', 'Medium', 'Low', 'Info')] [string] $Severity,
        [string] $Description,
        [ValidateSet('settingsCatalog', 'compliance', 'deviceConfiguration', 'tenantSetting')] [string] $Source = 'settingsCatalog',
        [string[]] $SettingDefinitionId = @(),
        [string] $Platform,
        [string] $Property,
        [string] $ODataType,
        [string[]] $Expected,
        [ValidateSet('eq', 'ne', 'gt', 'ge', 'lt', 'le', 'in', 'notIn', 'contains', 'match', 'exists')] [string] $Operator = 'eq',
        [string] $SettingDisplayName,
        [string] $ValueDisplayName,
        [string] $CategoryPath,
        [string] $FromPolicy,
        [string[]] $ChildSettingDefinitionId = @(),
        [string[]] $ChildExpected = @(),
        [string[]] $ChildDisplayName = @(),
        [string[]] $ChildValueDisplayName = @(),
        [ValidateSet('eq', 'ne', 'gt', 'ge', 'lt', 'le', 'in', 'notIn', 'contains', 'match', 'exists')] [string[]] $ChildOperator = @(),
        [switch] $NoChildren,
        [Parameter(ParameterSetName = 'Single')] [switch] $Replace,
        [string] $Level,
        [string] $Title,
        [ValidatePattern('^Test-[A-Za-z][A-Za-z0-9]*$')] [string] $FunctionName,
        [ValidateLength(1, 40)] [string] $Product,
        [ValidateLength(1, 60)] [string] $Feature,
        [ValidateLength(1, 60)] [string] $Area,
        [string] $Remediation,
        [string] $CspUrl,
        [string] $CspTitle,
        [string] $Author = 'Pacers31Colts18',
        [string] $SkipReason,
        [switch] $NoVersionBump,
        [string] $RepoPath = (Get-Location).Path,
        # Used by the -Path run: return the draft without asking ShouldProcess, and write without the Maester checks
        # (it runs them once, after every row).
        [Parameter(DontShow, ParameterSetName = 'Single')] [switch] $DraftOnly,
        [Parameter(DontShow, ParameterSetName = 'Single')] [switch] $SkipPackCheck,
        # Used by the -Path run: the test number of this row (its drafts are not on disk yet, so each row gets the
        # next one).
        [Parameter(DontShow, ParameterSetName = 'Single')] [ValidateRange(1, 999999)] [int] $Number
    )

    $ErrorActionPreference = 'Stop'
    Assert-JLMaester
    if ($PSCmdlet.ParameterSetName -eq 'Csv') {
        $defaults = @{}
        $runOnly = @('Path', 'RepoPath', 'WhatIf', 'Confirm') + [System.Management.Automation.PSCmdlet]::CommonParameters
        foreach ($key in $PSBoundParameters.Keys) { if ($key -notin $runOnly) { $defaults[$key] = $PSBoundParameters[$key] } }
        return New-JLMaesterTestBatch -Path $Path -Defaults $defaults -RepoPath $RepoPath
    }
    $repo = Resolve-JLPacksRepo -RepoPath $RepoPath
    $info = Resolve-JLPack -Repo $repo -Pack $Pack
    $code = [string]$info.Manifest.Code
    $benchmark = ([string]$info.Framework.Name -replace '\s*\([^)]*\)\s*$', '')
    # Tests are numbered in the order they are added (001, 002, ...); the recommendation is in Control and the .md.
    $testsDir = Join-Path $info.Path 'tests'
    # -Replace rewrites the test that checks the recommendation under its own number, keeping its Severity and
    # Description unless they are passed.
    $existing = $null
    $oldTitle = ''
    if ($Replace) {
        if ($Number) { throw '-Replace keeps the existing test''s number; leave out -Number.' }
        $controlLine = "^\s*Control\s*=\s*'$([regex]::Escape("$($info.FrameworkKey):$Recommendation"))'"
        $found = @(Get-ChildItem -LiteralPath $testsDir -Filter 'Test.*.ps1' | Where-Object { Select-String -LiteralPath $_.FullName -Pattern $controlLine -Quiet })
        if ($found.Count -ne 1) { throw "-Replace needs exactly one test of recommendation $Recommendation in $Pack; found $($found.Count)." }
        $existing = $found[0]
        $Number = [int][regex]::Match($existing.Name, '\.(\d+)\.ps1$').Groups[1].Value
        $oldPs1 = [System.IO.File]::ReadAllText($existing.FullName) -replace "`r`n", "`n"
        $oldTitle = [regex]::Match($oldPs1, "(?m)^\s*Title\s*=\s*'((?:[^']|'')*)'").Groups[1].Value.Replace("''", "'")
        if (-not $Severity) { $Severity = [regex]::Match($oldPs1, "(?m)^\s*Severity\s*=\s*'([^']+)'").Groups[1].Value }
        $oldMdPath = $existing.FullName -replace '\.ps1$', '.md'
        if (-not $PSBoundParameters.ContainsKey('Description') -and (Test-Path -LiteralPath $oldMdPath)) {
            # The Description section is the description, if any, then '<benchmark>, recommendation <n>'.
            $oldMd = [System.IO.File]::ReadAllText($oldMdPath) -replace "`r`n", "`n"
            $marker = "`n`n$benchmark, recommendation $Recommendation"
            $head = "#### Description`n`n"
            $at = $oldMd.IndexOf($marker)
            if ($oldMd.StartsWith($head) -and $at -gt $head.Length) { $Description = $oldMd.Substring($head.Length, $at - $head.Length) }
        }
    }
    if (-not $Severity) { throw 'Pass -Severity.' }
    if (-not $Number) { $Number = Get-JLNextTestNumber -TestsDir $testsDir -Code $code }
    $id = 'MP.{0}.{1:D3}' -f $code, $Number
    $ps1Path = Join-Path $testsDir "Test.$id.ps1"
    $mdPath = Join-Path $testsDir "Test.$id.md"
    if (-not $Replace) {
        if (Test-Path -LiteralPath $ps1Path) { throw "$id already exists: $ps1Path." }
        if (@($info.Framework.Requirements | Where-Object { [string]$_.Id -eq $Recommendation }).Count) { throw "Recommendation $Recommendation is already in tests/frameworks/$($info.FrameworkKey).json; pass -Replace to rewrite its test." }
    }

    # The pack's level: the framework file's Level, else the level every requirement shares.
    $packLevel = if ($info.Framework.PSObject.Properties['Level'] -and $info.Framework.Level) { [string]$info.Framework.Level }
    else {
        $levels = @($info.Framework.Requirements | ForEach-Object { [string]$_.Level } | Where-Object { $_ } | Select-Object -Unique)
        if ($levels.Count -eq 1) { $levels[0] } else { '' }
    }
    if (-not $Level) { $Level = $packLevel }

    # Product and Feature are the same for every test of a pack: Product from the framework file, Feature from its Name
    # with the pack's level, such as 'CIS Microsoft Intune for Windows 11 Benchmark (L1)', so -Feature picks one level.
    if (-not $Product) {
        if ($info.Framework.PSObject.Properties['Product'] -and $info.Framework.Product) { $Product = [string]$info.Framework.Product }
        else { throw "tests/frameworks/$($info.FrameworkKey).json has no Product; add one (such as `"Product`": `"Intune`") or pass -Product." }
    }
    if (-not $Feature) {
        if (-not $benchmark) { throw "tests/frameworks/$($info.FrameworkKey).json has no Name; add one or pass -Feature." }
        $Feature = if ($packLevel) { "$benchmark ($packLevel)" } else { $benchmark }
    }
    if ($Product.Length -gt 40) { throw "Product '$Product' is longer than 40 characters." }
    if ($Feature.Length -gt 60) { throw "Feature '$Feature' is longer than 60 characters." }

    # A skipped test checks no setting: it only names the recommendation and why the pack can't check it.
    if ($SkipReason) {
        $settingParams = @('FromPolicy', 'SettingDefinitionId', 'Platform', 'Property', 'ODataType', 'Expected', 'Operator', 'ChildSettingDefinitionId', 'ChildExpected', 'ChildDisplayName', 'ChildValueDisplayName', 'ChildOperator', 'NoChildren', 'CspUrl', 'CspTitle')
        $given = @($settingParams | Where-Object { $PSBoundParameters.ContainsKey($_) })
        if ($given.Count) { throw "-SkipReason writes a test that checks no setting; leave out -$($given -join ', -')." }
        if ($PSBoundParameters.ContainsKey('Source')) { throw '-SkipReason writes a test that checks no setting; leave out -Source.' }
        if (-not $SettingDisplayName) { throw 'With -SkipReason, pass -SettingDisplayName: what the recommendation configures, such as IIS Admin Service (IISADMIN).' }
        if (-not $ValueDisplayName) { throw 'With -SkipReason, pass -ValueDisplayName: the value the recommendation requires, such as Disabled.' }
        if (-not $Area) { throw 'With -SkipReason, pass -Area, such as System Services.' }
    }

    # Read the setting from a policy in the tenant
    $pickedChildren = $false
    $SettingDefinitionId = @($SettingDefinitionId | Where-Object { $_ })
    # Several settings that one recommendation needs, each checked on its own (Test-JlIntuneSetting): the same timer
    # under Desktop Power, Laptop Battery Power and Laptop Power.
    $several = $SettingDefinitionId.Count -gt 1
    # Each setting as the .md names it: its category path and name, from the policy.
    $settingPaths = @()
    $bare = { param($Text) ([string]$Text -replace ':\s*$', '').Trim() }
    if ($several) {
        if (-not $FromPolicy) { throw 'Several -SettingDefinitionId need -FromPolicy: their names and categories come from the policy.' }
        if ($Source -ne 'settingsCatalog') { throw '-FromPolicy reads settings catalog policies; use -Source settingsCatalog.' }
        if ($ChildSettingDefinitionId.Count -or $ChildExpected.Count -or $ChildDisplayName.Count -or $ChildValueDisplayName.Count -or $ChildOperator.Count) { throw 'Child settings go with one -SettingDefinitionId.' }
        $hits = @(foreach ($settingId in $SettingDefinitionId) {
                $found = @(Find-JLIntuneSetting -PolicyName $FromPolicy -SettingDefinitionId ([System.Management.Automation.WildcardPattern]::Escape($settingId)) | Where-Object { $_.Value.Count -gt 0 })
                if (-not $found.Count) { throw "No policy named like '$FromPolicy' sets '$settingId'." }
                $found
            })
        $first = @(foreach ($settingId in $SettingDefinitionId) { $hits | Where-Object SettingDefinitionId -EQ $settingId | Select-Object -First 1 })
        $names = @($first | ForEach-Object { & $bare $_.DisplayName } | Select-Object -Unique)
        if (-not $SettingDisplayName) { $SettingDisplayName = $names -join ', ' }
        $settingPaths = @($first | ForEach-Object { if ($_.CategoryPath) { "$($_.CategoryPath) > $(& $bare $_.DisplayName)" } else { & $bare $_.DisplayName } })
        # The category the settings share, such as Energy Saver for Desktop Power, Laptop Battery Power and Laptop Power.
        if (-not $CategoryPath) {
            $paths = @($first | ForEach-Object { , @([string]$_.CategoryPath -split '\s*>\s*' | Where-Object { $_ }) })
            $shared = @()
            for ($i = 0; $i -lt $paths[0].Count; $i++) {
                $part = $paths[0][$i]
                if (@($paths | Where-Object { $_.Count -le $i -or $_[$i] -ne $part }).Count) { break }
                $shared += $part
            }
            $CategoryPath = $shared -join ' > '
        }
        if (-not $Platform) { $Platform = (@($first[0].Platform -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -First 1) }
        if (-not $CspUrl -and $first[0].InfoUrls.Count) { $CspUrl = $first[0].InfoUrls[0] }
        if ($Operator -ne 'exists' -and -not $Expected) {
            # A choice setting's option ids differ per setting, so Expected is one value per setting, in order.
            $Expected = @(foreach ($hit in $first) {
                    $settingHits = @($hits | Where-Object SettingDefinitionId -EQ $hit.SettingDefinitionId)
                    if ($ValueDisplayName) {
                        $option = @($hit.Options | Where-Object DisplayName -EQ $ValueDisplayName)
                        if ($option.Count -ne 1) { throw "'$($hit.SettingDefinitionId)' has no option labelled '$ValueDisplayName'. Options: $(($hit.Options | ForEach-Object { "$($_.DisplayName) ($($_.ItemId))" }) -join ', ')." }
                        $option[0].ItemId
                    } else {
                        if (@($settingHits | ForEach-Object { $_.Value -join '|' } | Select-Object -Unique).Count -ne 1 -or $hit.Value.Count -ne 1) { throw "The matching policies set '$($hit.SettingDefinitionId)' to several values; pass -ValueDisplayName or -Expected." }
                        $hit.Value[0]
                    }
                })
            if (-not $ValueDisplayName) {
                $labels = @($first | ForEach-Object { $_.ValueDisplayName } | Select-Object -Unique)
                if ($labels.Count -ne 1) { throw "The settings have different values ($($labels -join ', ')); pass -ValueDisplayName." }
                $ValueDisplayName = $labels[0]
            }
        }
        Write-Verbose "From $FromPolicy`: $($SettingDefinitionId -join ', ') = $($Expected -join ', ') ($ValueDisplayName), category '$CategoryPath', platform $Platform."
    } elseif ($FromPolicy) {
        if ($Source -ne 'settingsCatalog') { throw '-FromPolicy reads settings catalog policies; use -Source settingsCatalog.' }
        if (-not $SettingDisplayName -and -not $SettingDefinitionId.Count) { throw 'With -FromPolicy, pass -SettingDisplayName or -SettingDefinitionId to pick the setting.' }
        $find = @{ PolicyName = $FromPolicy }
        # The id picks the setting on its own; a name given with it is only the title's (and may hold wildcard
        # characters, such as 'Windows 10 [Version 1511] and later').
        if ($SettingDefinitionId.Count) { $find.SettingDefinitionId = $SettingDefinitionId[0] }
        elseif ($SettingDisplayName) { $find.Name = $SettingDisplayName }
        $hits = @(Find-JLIntuneSetting @find | Where-Object { $_.Value.Count -gt 0 })
        $settingIds = @($hits | ForEach-Object { $_.SettingDefinitionId } | Select-Object -Unique)
        if ($settingIds.Count -ne 1) {
            $list = ($hits | ForEach-Object { "$($_.PolicyName): $($_.DisplayName) ($($_.SettingDefinitionId))" } | Select-Object -Unique) -join "`n - "
            throw "-FromPolicy found $($settingIds.Count) matching settings with a value$(if ($list) { ":`n - $list" } else { '.' })`nNarrow -SettingDisplayName or pass -SettingDefinitionId."
        }
        $hit = $hits[0]
        $SettingDefinitionId = @($hit.SettingDefinitionId)
        # Intune names some settings with a trailing space ('Backup Directory ') and many children like a form field
        # ('Protocol to use for outgoing RPC connections:'); both are left out of the title and .md ($bare).
        if (-not $SettingDisplayName -or [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($SettingDisplayName)) { $SettingDisplayName = & $bare $hit.DisplayName }
        if (-not $CategoryPath) { $CategoryPath = $hit.CategoryPath }
        if (-not $Platform) { $Platform = (@($hit.Platform -split ',') | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -First 1) }
        if (-not $CspUrl -and $hit.InfoUrls.Count) { $CspUrl = $hit.InfoUrls[0] }
        # exists checks only that the setting has a value, so the policy's value is not read: it would end up in the
        # test file and .md (for a logon message, the tenant's own text).
        if ($Operator -ne 'exists' -and -not $Expected) {
            if ($ValueDisplayName) {
                $option = @($hit.Options | Where-Object DisplayName -EQ $ValueDisplayName)
                if ($option.Count -ne 1) { throw "'$SettingDisplayName' has no option labelled '$ValueDisplayName'. Options: $(($hit.Options | ForEach-Object { "$($_.DisplayName) ($($_.ItemId))" }) -join ', ')." }
                $Expected = $option[0].ItemId
            } else {
                $values = @($hits | ForEach-Object { $_.Value -join '|' } | Select-Object -Unique)
                if ($values.Count -ne 1) { throw "The matching policies set '$SettingDisplayName' to different values; pass -ValueDisplayName to pick the required one." }
                $Expected = $hit.Value
                $ValueDisplayName = $hit.ValueDisplayName
                # Several values (such as the accounts of a user right): every configured value must be one of them.
                if (@($Expected).Count -gt 1 -and -not $PSBoundParameters.ContainsKey('Operator')) { $Operator = 'in' }
            }
        }
        Write-Verbose "From $($hit.PolicyName): $SettingDefinitionId = $($Expected -join ', ') ($ValueDisplayName), category '$CategoryPath', platform $Platform."

        # The children the same policy configures under the setting (any depth), with their values and names: all of
        # them, or only the ones -ChildSettingDefinitionId picks (one test per child of a parent with several, as CIS
        # numbers them). Values and names given with picked children replace the policy's (such as 16384 and
        # '16,384 KB or more' for a size 'or greater'); the policy must still configure each picked child.
        if (-not $NoChildren) {
            $pick = @($ChildSettingDefinitionId)
            $givenExpected = @($ChildExpected)
            $givenNames = @($ChildDisplayName)
            $givenValues = @($ChildValueDisplayName)
            if (-not $pick.Count -and ($givenExpected.Count -or $givenNames.Count -or $givenValues.Count)) { throw 'With -FromPolicy, -ChildExpected, -ChildDisplayName and -ChildValueDisplayName are for picked children: pass -ChildSettingDefinitionId too.' }
            foreach ($given in @(@{ Name = 'ChildExpected'; Value = $givenExpected }, @{ Name = 'ChildDisplayName'; Value = $givenNames }, @{ Name = 'ChildValueDisplayName'; Value = $givenValues })) {
                if ($given.Value.Count -and $given.Value.Count -ne $pick.Count) { throw "-ChildSettingDefinitionId has $($pick.Count) value(s) and -$($given.Name) $($given.Value.Count); pass one per picked child." }
            }
            $ChildExpected = @()
            $ChildDisplayName = @()
            $ChildValueDisplayName = @()
            $ChildSettingDefinitionId = @()
            $rows = @(Find-JLIntuneSetting -PolicyName $hit.PolicyName | Where-Object PolicyId -EQ $hit.PolicyId)
            $byId = @{}
            foreach ($row in $rows) { $byId[$row.SettingDefinitionId] = $row }
            $found = @(foreach ($row in $rows) {
                if ($row.SettingDefinitionId -eq $hit.SettingDefinitionId -or $row.Value.Count -eq 0) { continue }
                $parent = $row.ParentSettingDefinitionId
                for ($depth = 0; $parent -and $parent -ne $hit.SettingDefinitionId -and $depth -lt 10; $depth++) { $parent = if ($byId.ContainsKey($parent)) { $byId[$parent].ParentSettingDefinitionId } else { '' } }
                if ($parent -eq $hit.SettingDefinitionId) { $row }
            })
            if ($pick.Count) {
                $pickedChildren = $true
                $available = ($found | ForEach-Object { "$($_.SettingDefinitionId) ($(& $bare $_.DisplayName))" } | Select-Object -Unique) -join ', '
                $found = @(foreach ($childId in $pick) {
                    $match = @($found | Where-Object SettingDefinitionId -EQ $childId | Select-Object -First 1)
                    if (-not $match.Count) { throw "-ChildSettingDefinitionId '$childId' is not one of the children $($hit.PolicyName) configures under '$SettingDisplayName'$(if ($available) { ": $available" } else { ' (it configures none)' })." }
                    $match[0]
                })
            }
            foreach ($row in $found) {
                # A list child (such as a deny list of setup classes) holds several values: only a picked child whose
                # values are given can be checked, as the policy's values alone don't say whether the list must
                # include them (contains) or be limited to them (in).
                if ($row.Value.Count -ne 1 -and -not ($pick.Count -and $givenExpected.Count)) { throw "The child setting '$($row.DisplayName)' has $($row.Value.Count) values; pick it with -ChildSettingDefinitionId and pass -ChildExpected (the values separated by '|') with -ChildOperator contains or in, or pass -NoChildren." }
                $ChildSettingDefinitionId += $row.SettingDefinitionId
                $ChildExpected += [string](@($row.Value) -join '|')
                $ChildDisplayName += $(if ($row.DisplayName) { & $bare $row.DisplayName } else { $row.SettingDefinitionId })
                $ChildValueDisplayName += $row.ValueDisplayName
            }
            if ($givenExpected.Count) { $ChildExpected = $givenExpected }
            if ($givenNames.Count) { $ChildDisplayName = $givenNames }
            if ($givenValues.Count) { $ChildValueDisplayName = $givenValues }
            if ($ChildSettingDefinitionId.Count) { Write-Verbose "Children from $($hit.PolicyName): $(@(for ($i = 0; $i -lt $ChildSettingDefinitionId.Count; $i++) { "$($ChildDisplayName[$i]) = $($ChildValueDisplayName[$i])" }) -join '; ')." }
        }
    }

    # Check the inputs
    $childCount = $ChildSettingDefinitionId.Count
    if (-not $SkipReason) {
        if ($Source -eq 'settingsCatalog') {
            if (-not $SettingDefinitionId.Count) { throw 'Source settingsCatalog needs -SettingDefinitionId (or -FromPolicy).' }
            if (-not $Platform) { $Platform = 'windows10' }
            if ($Property -or $ODataType) { throw '-Property and -ODataType are for the compliance and deviceConfiguration sources.' }
        } else {
            if ($Source -eq 'tenantSetting') {
                if (-not $Property) { throw 'Source tenantSetting needs -Property.' }
                if ($ODataType) { throw '-ODataType is for the compliance and deviceConfiguration sources.' }
            } elseif (-not $Property -or -not $ODataType) { throw "Source $Source needs -Property and -ODataType." }
            if ($SettingDefinitionId.Count -or $Platform) { throw '-SettingDefinitionId and -Platform are for the settingsCatalog source.' }
        }
        if ($Operator -ne 'exists' -and -not $Expected) { throw "Operator $Operator needs -Expected (or -FromPolicy)." }
        if ($several) {
            if ($Operator -ne 'exists' -and @($Expected).Count -notin 1, $SettingDefinitionId.Count) { throw "-SettingDefinitionId has $($SettingDefinitionId.Count) settings and -Expected $(@($Expected).Count) values; pass one value for all of them, or one per setting (a setting's values for in, notIn and contains separated by '|')." }
        } elseif ($Operator -notin 'in', 'notIn', 'contains' -and @($Expected).Count -gt 1) { throw "Operator $Operator takes one expected value; in, notIn and contains take several." }
        if (-not $SettingDisplayName) { throw 'Pass -SettingDisplayName: the setting''s name as Intune shows it.' }
        if ($Operator -ne 'exists' -and -not $ValueDisplayName) { throw 'Pass -ValueDisplayName: the required value''s label, such as Block.' }
        if ($ChildOperator.Count -and $ChildOperator.Count -ne $childCount) { throw "-ChildSettingDefinitionId has $childCount value(s) and -ChildOperator $($ChildOperator.Count); pass one operator per child setting, or none for eq." }
        if ($childCount) {
            if ($Source -ne 'settingsCatalog') { throw 'Child settings are for the settingsCatalog source.' }
            # An exists child needs no value: it is written empty, whatever the policy sets.
            if ($ChildOperator.Count) {
                if (-not $ChildExpected.Count) { $ChildExpected = @($ChildOperator | ForEach-Object { '' }) }
                $ChildExpected = @(for ($i = 0; $i -lt $childCount; $i++) { if ($ChildOperator[$i] -eq 'exists') { '' } else { $ChildExpected[$i] } })
                # The policy's value is not named either (read with -FromPolicy, it would be its own value).
                $namedByHand = $PSBoundParameters.ContainsKey('ChildValueDisplayName')
                $ChildValueDisplayName = @(for ($i = 0; $i -lt $childCount; $i++) { if ($ChildOperator[$i] -eq 'exists' -and -not ($namedByHand -and $ChildValueDisplayName[$i])) { 'any value' } else { $ChildValueDisplayName[$i] } })
            }
            foreach ($pair in @{ ChildExpected = $ChildExpected; ChildDisplayName = $ChildDisplayName; ChildValueDisplayName = $ChildValueDisplayName }.GetEnumerator()) {
                if (@($pair.Value).Count -ne $childCount) { throw "-ChildSettingDefinitionId has $childCount value(s) and -$($pair.Key) $(@($pair.Value).Count); pass one of each per child setting." }
            }
        } elseif ($ChildExpected.Count -or $ChildDisplayName.Count -or $ChildValueDisplayName.Count) { throw 'Pass -ChildSettingDefinitionId with the other -Child parameters.' }
    }
    # Area defaults to the setting's own Intune category, the last level of the path: 'Administrative Templates >
    # System > Power Management > Sleep Settings' becomes 'Sleep Settings'. The .md keeps the whole path.
    if (-not $Area) {
        if (-not $CategoryPath) { throw 'Pass -Area: there is no Intune category path to take it from (-CategoryPath, or read by -FromPolicy).' }
        $fromCategory = @($CategoryPath -split '\s*>\s*' | ForEach-Object { $_.Trim() } | Where-Object { $_ })[-1]
        if ($fromCategory.Length -gt 60) { throw "Pass -Area: '$fromCategory', the Intune category, is longer than Maester's 60 characters." }
        $Area = $fromCategory
    }

    # Picked children (-FromPolicy -ChildDisplayName) are named in the title and the function, as CIS writes them:
    # '<setting>: <child> is set to Enabled: <child value>', so the tests of a parent's children don't collide.
    $settingName = if ($pickedChildren) { "${SettingDisplayName}: $($ChildDisplayName -join ', ')" } else { $SettingDisplayName }
    if (-not $Title) {
        # The title says what passes in words: 'includes Guests', 'is at least 180', not the operator.
        $Title = switch ($Operator) {
            'exists' { "$settingName is configured" }
            { $_ -in 'ne', 'notIn' } { "$settingName is not set to $ValueDisplayName" }
            'contains' { "$settingName includes $ValueDisplayName" }
            'ge' { "$settingName is at least $ValueDisplayName" }
            'gt' { "$settingName is more than $ValueDisplayName" }
            'le' { "$settingName is at most $ValueDisplayName" }
            'lt' { "$settingName is less than $ValueDisplayName" }
            default { "$settingName is set to $ValueDisplayName" }
        }
        if ($childCount) { $Title += ": $($ChildValueDisplayName -join ', ')" }
    }
    # The function is named after what the test checks, so it is unique in the pack even when two settings share a
    # display name (the four event logs): the setting definition id without the prefix every id shares
    # (device_vendor_msft_policy_config_), or the picked child's id; for compliance and deviceConfiguration the
    # policy type and property; a skipped test's display name. abovelock_allowtoasts gives Test-JLAbovelockAllowtoasts.
    if (-not $FunctionName) {
        $stripId = { param($Id) $user = $Id -like 'user_*'; $rest = $Id -replace '^(device_|user_)?vendor_msft_(policy_config_)?', ''; if ($user) { "user_$rest" } else { $rest } }
        $nameSource = if ($SkipReason) { $SettingDisplayName }
        elseif ($Source -ne 'settingsCatalog') { "$($ODataType -replace '^#?microsoft\.graph\.', '') $Property" }
        elseif ($pickedChildren) { (@($ChildSettingDefinitionId) | ForEach-Object { & $stripId $_ }) -join ' ' }
        elseif ($several) {
            # The '_' parts every id shares at its start and end: com.apple.mcx_..._display sleep timer under the three
            # power sources gives com.apple.mcx display sleep timer.
            $parts = @($SettingDefinitionId | ForEach-Object { , @((& $stripId $_) -split '_') })
            $shortest = ($parts | ForEach-Object { $_.Count } | Measure-Object -Minimum).Minimum
            $head = @(for ($i = 0; $i -lt $shortest; $i++) { $part = $parts[0][$i]; if (@($parts | Where-Object { $_[$i] -ne $part }).Count) { break }; $part })
            $tail = @(for ($i = 1; $i -le $shortest - $head.Count; $i++) { $part = $parts[0][-$i]; if (@($parts | Where-Object { $_[-$i] -ne $part }).Count) { break }; $part })
            [array]::Reverse($tail)
            $common = @($head) + @($tail)
            if ($common.Count) { $common -join ' ' } else { & $stripId $SettingDefinitionId[0] }
        }
        else { & $stripId $SettingDefinitionId[0] }
        $FunctionName = 'Test-JL' + (ConvertTo-JLPascalCase -Text $nameSource)
    }
    foreach ($file in (Get-ChildItem -LiteralPath $testsDir -Filter 'Test.*.ps1')) {
        if ($existing -and $file.FullName -eq $existing.FullName) { continue }
        if (Select-String -LiteralPath $file.FullName -Pattern "^function $([regex]::Escape($FunctionName))\b" -Quiet) { throw "$($file.Name) already defines $FunctionName; pass -FunctionName." }
    }

    # The test file
    $attribute = [ordered]@{
        Id           = $id
        Title        = $Title
        Product      = $Product
        Feature      = $Feature
        Area         = $Area
        ResourceType = 'Policy'
        Severity     = $Severity
        Control      = "$($info.FrameworkKey):$Recommendation"
        Service      = 'Graph'
        License      = 'INTUNE_A'
        Permission   = 'Graph:Scope:DeviceManagementConfiguration.Read.All'
        Author       = $Author
    }
    $attributeLines = @($attribute.Keys | ForEach-Object { '        {0,-12} = {1}' -f $_, (ConvertTo-JLQuoted -Text ([string]$attribute[$_])) })
    # @($null) is one item; an exists test has no expected value and gets none.
    $expectedLiteral = (@($Expected | Where-Object { $null -ne $_ }) | ForEach-Object { ConvertTo-JLQuoted -Text ([string]$_) }) -join ', '
    # Inside param() a bare comma starts the next parameter, so a list default needs parentheses.
    if (@($Expected).Count -gt 1) { $expectedLiteral = "($expectedLiteral)" }
    $expectedLine = if ($expectedLiteral) { "        [string[]] `$Expected = $expectedLiteral," } else { '        [string[]] $Expected,' }
    $listLiteral = {
        param([string[]] $Values)
        $text = (@($Values) | ForEach-Object { ConvertTo-JLQuoted -Text ([string]$_) }) -join ', '
        if (@($Values).Count -gt 1) { "($text)" } else { $text }
    }

    # ChildOperator is written only when a child is not compared with eq, so eq-only tests keep the plain template.
    $childOperators = @($ChildOperator | Where-Object { $_ -ne 'eq' }).Count -gt 0
    $ps1 = [System.Collections.Generic.List[string]]::new()
    $ps1.Add("function $FunctionName {")
    $ps1.Add('    [MaesterTest(')
    $ps1.Add(($attributeLines -join ",`n"))
    $ps1.Add('    )]')
    $ps1.Add('    [CmdletBinding()]')
    $ps1.Add('    [OutputType([bool])]')
    if ($SkipReason) {
        $ps1.Add('    param(')
        $ps1.Add('        # Why the pack can''t check this recommendation; the report shows it as the skip reason.')
        $ps1.Add("        [string] `$SkipReason = $(ConvertTo-JLQuoted -Text $SkipReason)")
        $ps1.Add('    )')
        $ps1.Add('')
        $ps1.Add('    Add-MtTestResultDetail -SkippedBecause Custom -SkippedCustomReason $SkipReason')
        $ps1.Add('    return $null')
        $ps1.Add('}')
    } else {
        $ps1.Add('    param(')
        $ps1.Add('        # Where the setting lives: settingsCatalog, compliance, deviceConfiguration or tenantSetting.')
        $ps1.Add("        [ValidateSet('settingsCatalog', 'compliance', 'deviceConfiguration', 'tenantSetting')]")
        $ps1.Add("        [string] `$Source = '$Source',")
        $ps1.Add('')
        if ($Source -eq 'settingsCatalog') {
            $ps1.Add('        # settingsCatalog only: the platform the policy targets.')
            $ps1.Add("        [string] `$Platform = $(ConvertTo-JLQuoted -Text $Platform),")
            $ps1.Add('')
            if ($several) {
                $ps1.Add('        # The settings catalog setting definition ids to check; each must pass on its own.')
                $ps1.Add("        [string[]] `$SettingDefinitionId = $(& $listLiteral $SettingDefinitionId),")
            } else {
                $ps1.Add('        # The settings catalog setting definition id to check.')
                $ps1.Add("        [string] `$SettingDefinitionId = $(ConvertTo-JLQuoted -Text $SettingDefinitionId[0]),")
            }
        } else {
            if ($ODataType) {
                $ps1.Add('        # compliance / deviceConfiguration only: the policy type, such as #microsoft.graph.windows10CompliancePolicy.')
                $ps1.Add("        [string] `$ODataType = $(ConvertTo-JLQuoted -Text $ODataType),")
                $ps1.Add('')
            }
            $ps1.Add('        # The property to check, dots for nested.')
            $ps1.Add("        [string] `$Property = $(ConvertTo-JLQuoted -Text $Property),")
        }
        $ps1.Add('')
        if ($several) { $ps1.Add('        # The value each setting requires, in the same order, or one value for all of them (the option id for a choice setting).') }
        else { $ps1.Add('        # The value the recommendation requires (the option id for a choice setting).') }
        $ps1.Add($expectedLine)
        $ps1.Add('')
        if ($childCount) {
            $ps1.Add('        # Child settings that must be set in the same policy, each to the ChildExpected value in the same position.')
            $ps1.Add("        [string[]] `$ChildSettingDefinitionId = $(& $listLiteral $ChildSettingDefinitionId),")
            $ps1.Add('')
            $ps1.Add('        # The value each child setting requires (the option id for a choice setting).')
            $ps1.Add("        [string[]] `$ChildExpected = $(& $listLiteral $ChildExpected),")
            $ps1.Add('')
            if ($childOperators) {
                $ps1.Add("        # How each child setting is compared with its ChildExpected: eq, ge, in (values separated by |), exists, ...")
                $ps1.Add("        [string[]] `$ChildOperator = $(& $listLiteral $ChildOperator),")
                $ps1.Add('')
            }
        }
        $ps1.Add("        # Only policies whose name matches this wildcard count, such as 'W11-CIS-*'. Empty uses the JLIntune.PolicyNameFilter setting.")
        $ps1.Add('        [string] $PolicyNameFilter,')
        $ps1.Add('')
        $ps1.Add('        # Count policies that are not assigned to anything.')
        $ps1.Add('        [bool] $IncludeUnassigned = $false,')
        $ps1.Add('')
        $ps1.Add('        # Pass even when a counted policy sets a value that does not meet the requirement.')
        $ps1.Add('        [bool] $AllowConflicts = $false')
        $ps1.Add('    )')
        $ps1.Add('')
        # The splat's = signs line up under its longest key.
        $splat = [ordered]@{ Source = '$Source' }
        if ($Source -eq 'settingsCatalog') { $splat.Platform = '$Platform'; $splat.SettingDefinitionId = '$SettingDefinitionId' }
        else {
            if ($ODataType) { $splat.ODataType = '$ODataType' }
            $splat.Property = '$Property'
        }
        $splat.Operator = "'$Operator'"
        $splat.Expected = '$Expected'
        if ($childCount) { $splat.ChildSettingDefinitionId = '$ChildSettingDefinitionId'; $splat.ChildExpected = '$ChildExpected' }
        if ($childOperators) { $splat.ChildOperator = '$ChildOperator' }
        $splat.PolicyNameFilter = '$PolicyNameFilter'
        $splat.IncludeUnassigned = '$IncludeUnassigned'
        $splat.AllowConflicts = '$AllowConflicts'
        # A plain loop: ForEach-Object <property> asks ShouldProcess, so -WhatIf would print a line per key.
        $width = 19
        foreach ($key in $splat.Keys) { if ($key.Length -gt $width) { $width = $key.Length } }
        $ps1.Add('    $Params = @{')
        foreach ($key in $splat.Keys) { $ps1.Add(("        {0,-$width} = {1}" -f $key, $splat[$key])) }
        $ps1.Add('    }')
        $ps1.Add('')
        $ps1.Add('    Test-JlIntuneSetting @Params')
        $ps1.Add('}')
    }
    $ps1Text = $ps1 -join "`n"

    # The markdown file
    $platformShort = switch ($Platform) { 'windows10' { 'Windows' } '' { '' } default { $Platform } }
    $platformLong = switch ($Platform) { 'windows10' { 'Windows 10 and later' } default { $Platform } }
    # Names and values are written as Markdown, so its characters are escaped: \\*\NETLOGON would show as \*\NETLOGON.
    $esc = { param($Text) [string]$Text -replace '([\\`*_])', '\$1' }
    $mdSetting = & $esc $SettingDisplayName
    $mdValue = & $esc $ValueDisplayName
    $mdChildName = @($ChildDisplayName | ForEach-Object { & $esc $_ })
    $mdChildValue = @($ChildValueDisplayName | ForEach-Object { & $esc $_ })
    $settingPath = if ($CategoryPath) { "$(& $esc $CategoryPath) > $mdSetting" } else { $mdSetting }
    # In remediation steps each part of the path is bold on its own, as the Intune UI shows them: **Above Lock** > **Allow Cortana Above Lock**.
    $settingSteps = (@($settingPath -split ' > ') | ForEach-Object { "**$_**" }) -join ' > '
    $valueText = switch ($Operator) {
        'exists' { 'any value' }
        { $_ -in 'ne', 'notIn' } { "any value other than **$mdValue**" }
        'contains' { "a list that includes **$mdValue**" }
        'ge' { "**$mdValue** or more" }
        'gt' { "more than **$mdValue**" }
        'le' { "**$mdValue** or less" }
        'lt' { "less than **$mdValue**" }
        default { "**$mdValue**" }
    }
    $policyKind = switch ($Source) { 'settingsCatalog' { "settings catalog policy for $platformShort" } 'compliance' { 'compliance policy' } 'deviceConfiguration' { 'configuration profile' } 'tenantSetting' { 'tenant setting' } }
    # Child settings, as the Intune UI shows them under the setting: **Configure MrxSmb10 driver** set to **Disable driver**.
    $childPasses = ''
    $childSteps = ''
    if ($childCount) {
        $childPasses = ", with $(@(for ($i = 0; $i -lt $childCount; $i++) { "**$($mdChildName[$i])** set to **$($mdChildValue[$i])**" }) -join ' and ') in the same policy"
        $childSteps = ", then set $(@(for ($i = 0; $i -lt $childCount; $i++) { "**$($mdChildName[$i])** to **$($mdChildValue[$i])**" }) -join ' and ')"
    }
    $passes = "The test passes when an assigned $policyKind sets **$settingPath** to $valueText$childPasses, and no other assigned policy sets it to something else."
    if ($several) {
        # Each setting by its own path, as the Intune UI shows it: **Energy Saver** > **Desktop Power** > **Display Sleep Timer**.
        $joinAnd = { param([string[]] $Items) if ($Items.Count -le 1) { $Items -join '' } else { "$($Items[0..($Items.Count - 2)] -join ', ') and $($Items[-1])" } }
        $mdPaths = @($settingPaths | ForEach-Object { & $esc $_ })
        $settingSteps = & $joinAnd @($mdPaths | ForEach-Object { (@($_ -split ' > ') | ForEach-Object { "**$_**" }) -join ' > ' })
        $passes = "The test passes when assigned $($policyKind -replace '^settings catalog policy', 'settings catalog policies') set each of $(& $joinAnd @($mdPaths | ForEach-Object { "**$_**" })) to $valueText, and no other assigned policy sets one of them to something else."
    }
    if ($Source -eq 'tenantSetting') { $passes = "The test passes when the tenant's Compliance policy settings set **$settingPath** to $valueText." }
    if ($SkipReason) { $passes = "This test is always skipped: $($SkipReason.Trim().TrimEnd('.')). Check **$mdSetting** on the devices, or in the results of the script that sets it." }
    $levelText = if ($Level -match '^L(\d+)$') { " (Level $($Matches[1]))" } elseif ($Level) { " ($Level)" } else { '' }
    if (-not $Remediation -and $SkipReason) {
        $Remediation = "1. In the [Microsoft Intune admin center](https://intune.microsoft.com), go to **Devices** > **Scripts and remediations**.`n2. Set **$mdSetting** to **$mdValue** with a remediation or platform script, and assign it to your devices."
    } elseif (-not $Remediation) {
        $Remediation = switch ($Source) {
            'settingsCatalog' {
                "1. In the [Microsoft Intune admin center](https://intune.microsoft.com), go to **Devices** > **Configuration** and open`n   (or create) a settings catalog policy for $platformLong.`n2. Add $settingSteps and set $(if ($several) { 'each' } else { 'it' }) to $valueText$childSteps.`n3. Assign the policy to your $(if ($platformShort) { "$platformShort " })devices, and remove any other assigned policy that sets $(if ($several) { 'one of them' } else { 'it' }) to something else."
            }
            'compliance' {
                "1. In the [Microsoft Intune admin center](https://intune.microsoft.com), go to **Devices** > **Compliance** and open (or create)`n   the compliance policy.`n2. Set $settingSteps to $valueText.`n3. Assign the policy to your devices, and remove any other assigned compliance policy that sets it to something else."
            }
            'tenantSetting' {
                "1. In the [Microsoft Intune admin center](https://intune.microsoft.com), go to **Devices** > **Compliance** > **Compliance policy settings**.`n2. Set $settingSteps to $valueText."
            }
            'deviceConfiguration' {
                "1. In the [Microsoft Intune admin center](https://intune.microsoft.com), go to **Devices** > **Configuration** and open the`n   configuration profile.`n2. Set $settingSteps to $valueText.`n3. Assign the profile to your devices, and remove any other assigned profile that sets it to something else."
            }
        }
    }
    # Related links is the Microsoft Learn page only (remediation step 1 already links the admin center); without one
    # the section is left out.
    $links = if ($CspUrl) { @('#### Related links', '', "- [$(if ($CspTitle) { $CspTitle } else { 'Microsoft Learn' })]($CspUrl)", '') } else { @() }
    # The Description section names the recommendation (the test ID is only a number), after -Description when given.
    $intro = @('#### Description', '')
    if ($Description -and $Description.Trim()) { $intro += @($Description.Trim(), '') }
    $intro += @("$benchmark, recommendation $Recommendation$levelText.", '', $passes)
    $mdText = @(
        $intro
        ''
        '#### Remediation action'
        ''
        $Remediation.Trim()
        ''
        $links
        '<!--- Results --->'
        '%TestResult%'
    ) -join "`n"

    # Version and records
    $current = [string]$info.Manifest.Version
    $released = Test-JLPackReleased -Repo $repo -Folder $Pack -Version $current
    $version = $current
    if ($released -and -not $NoVersionBump) {
        $parts = $current.Split('.')
        $version = "$($parts[0]).$([int]$parts[1] + 1).0"
    }
    $result = [pscustomobject]@{
        Id                  = $id
        Title               = $Title
        FunctionName        = $FunctionName
        Area                = $Area
        SettingDefinitionId = $(if ($SkipReason) { '' } elseif ($Source -ne 'settingsCatalog') { $Property } elseif ($several) { , @($SettingDefinitionId) } else { $SettingDefinitionId[0] })
        Expected            = @($Expected | Where-Object { $null -ne $_ })
        Children            = @(for ($i = 0; $i -lt $childCount; $i++) { [pscustomobject]@{ SettingDefinitionId = $ChildSettingDefinitionId[$i]; Operator = $(if ($ChildOperator.Count) { $ChildOperator[$i] } else { 'eq' }); Expected = $ChildExpected[$i]; DisplayName = $ChildDisplayName[$i]; ValueDisplayName = $ChildValueDisplayName[$i] } })
        # With -Replace, the title of the test it rewrites.
        Replaces            = $oldTitle
        Level               = $Level
        PackVersion         = $version
        Files               = @($ps1Path, $mdPath)
        Ps1                 = $ps1Text
        Markdown            = $mdText
    }
    $action = if ($Replace) { "Replace test $id '$oldTitle' with '$Title'" } else { "Create test $id '$Title'" }
    if ($DraftOnly -or -not $PSCmdlet.ShouldProcess($ps1Path, "$action (pack version $version)")) { return $result }

    $changelogPath = Join-Path $repo 'CHANGELOG.md'
    $state = Save-JLFileState -Path $ps1Path, $mdPath, $info.FrameworkPath, $info.ReadmePath, $changelogPath, $info.ManifestPath
    # Undone in finally, not catch: a stopped run (Ctrl+C) skips catch blocks but still runs finally.
    $done = $false
    try {
        Write-JLTextFile -Path $ps1Path -Text $ps1Text
        Write-JLTextFile -Path $mdPath -Text $mdText

        # A replaced test keeps its framework requirement; its README row and CHANGELOG line are rewritten.
        if (-not $Replace) {
            $requirement = [ordered]@{ Id = $Recommendation }
            if ($Level) { $requirement.Level = $Level }
            $framework = $info.Framework
            $requirements = @(@($framework.Requirements | Where-Object { $null -ne $_ }) + [pscustomobject]$requirement | Sort-Object { Get-JLRecommendationSortKey -Recommendation ([string]$_.Id) })
            $framework.Requirements = $requirements
            Write-JLFrameworkFile -Path $info.FrameworkPath -Framework $framework
        } else {
            $readme = @(([System.IO.File]::ReadAllText($info.ReadmePath) -replace "`r`n", "`n").TrimEnd("`n").Split("`n") | Where-Object { -not $_.StartsWith("| $id |") })
            Write-JLTextFile -Path $info.ReadmePath -Text ($readme -join "`n")
        }

        $prefix = "| MP.$code."
        Add-JLMarkdownTableRow -Path $info.ReadmePath -Header '| ID | Recommendation # | Title | Severity |' -Row "| $id | $Recommendation | $($Title.Replace('|', '\|')) | $Severity |" -SortKey {
            $cell = ($_ -split '\|')[1].Trim()
            Get-JLRecommendationSortKey -Recommendation ($cell.Substring($prefix.Length - 2))
        }
        if ($version -ne $current) { Set-JLPackVersion -ManifestPath $info.ManifestPath -Version $version -Confirm:$false }
        # A replaced test's line in this version's section is rewritten in place; a released one gets a new line.
        $changelog = @(([System.IO.File]::ReadAllText($changelogPath) -replace "`r`n", "`n").TrimEnd("`n").Split("`n"))
        $sectionStart = [array]::IndexOf($changelog, "## $Pack $version")
        $oldLine = -1
        if ($Replace -and $sectionStart -ge 0) {
            for ($i = $sectionStart + 1; $i -lt $changelog.Count -and -not $changelog[$i].StartsWith('## '); $i++) { if ($changelog[$i].StartsWith("- **$id** ")) { $oldLine = $i; break } }
        }
        if ($oldLine -ge 0) {
            $changelog[$oldLine] = "- **$id** $Title"
            Write-JLTextFile -Path $changelogPath -Text ($changelog -join "`n")
        } else {
            Add-JLChangelogLine -Path $changelogPath -Folder $Pack -Version $version -Line "- **$id** $Title"
        }

        if (-not $SkipPackCheck) {
            $written = @(Get-MtTest -Path $info.Path | Where-Object Id -EQ $id)
            if ($written.Count -ne 1) { throw "Get-MtTest did not find $id after writing it." }
            if (-not $written[0].IsValid) { throw "Get-MtTest rejects $($id): $(@($written[0].Errors | ForEach-Object { if ($_.Message) { $_.Message } else { "$_" } }) -join '; ')" }
            if ([string]$written[0].Benchmark.Requirement -ne $Recommendation) { throw "$id does not resolve to requirement $Recommendation of $($info.FrameworkKey)." }
            $check = Test-MtPack $info.Path
            if (-not $check.IsValid -or $check.Risk -ne 'Low' -or @($check.Findings).Count) { throw "Test-MtPack rejects the pack after adding $($id): $(@($check.Errors | ForEach-Object { $_.Message }) -join '; ')" }
        }
        $done = $true
    } finally {
        if (-not $done) { Restore-JLFileState -State $state }
    }
    $result
}
