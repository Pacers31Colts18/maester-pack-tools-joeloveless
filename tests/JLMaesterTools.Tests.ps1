# Pester tests of JLMaesterTools. Each test builds a packs repository in TestDrive and runs the real Maester checks
# (Test-MtPack, Get-MtTest, Invoke-MtTest) on what the module writes. Graph calls are mocked. Run: Invoke-Pester ./tests

BeforeAll {
    Import-Module Maester -MinimumVersion 3.0.0
    Import-Module Microsoft.Graph.Authentication
    Import-Module (Join-Path $PSScriptRoot '../JLMaesterTools/JLMaesterTools.psd1') -Force

    function New-FixtureRepo {
        $repo = Join-Path $TestDrive ([guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path (Join-Path $repo 'shared/helpers') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $repo 'shared/helpers/Test-JlIntuneSetting.ps1') -Value @'
function Test-JlIntuneSetting {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments)] $Rest)
    $true
}
'@
        Set-Content -LiteralPath (Join-Path $repo 'README.md') -Value "# Fixture packs`n`n## Packs`n`n| Pack | Folder | Code | Checks |`n| --- | --- | --- | --- |`n"
        Set-Content -LiteralPath (Join-Path $repo 'CHANGELOG.md') -Value "# Changelog`n"
        $repo
    }

    function New-FixturePack([string] $Repo) {
        New-JLMaesterPack -RepoPath $Repo -Folder cis-win11-intune-l1 -Code JL.CISW11INT.L1 -Name 'CIS Windows 11 Intune L1' `
            -FrameworkKey cis-intune-win11-l1 -BenchmarkName 'CIS Microsoft Intune for Windows 11 Benchmark' -BenchmarkVersion 5.0.0 `
            -BenchmarkUrl https://www.cisecurity.org/benchmark/intune -Level L1 -Tags CIS-Intune, L1 -InformationAction SilentlyContinue
    }

    $script:Cortana = @{
        Pack                = 'cis-win11-intune-l1'
        Recommendation      = '1.1'
        Severity            = 'High'
        Platform            = 'windows10'
        SettingDefinitionId = 'device_vendor_msft_policy_config_abovelock_allowcortanaabovelock'
        Expected            = 'device_vendor_msft_policy_config_abovelock_allowcortanaabovelock_0'
        SettingDisplayName  = 'Allow Cortana Above Lock'
        ValueDisplayName    = 'Block'
        CategoryPath        = 'Above Lock'
        Description         = 'Cortana should not answer voice requests while the device is locked.'
        # Product and Feature come from the framework file.
        Area                = 'Above Lock'
    }

    # The test file of the pack repository's first test, as the template writes it.
    $script:CortanaPs1 = @'
function Test-JLAbovelockAllowcortanaabovelock {
    [MaesterTest(
        Id           = 'MP.JL.CISW11INT.L1.001',
        Title        = 'Allow Cortana Above Lock is set to Block',
        Product      = 'Intune',
        Feature      = 'CIS Microsoft Intune for Windows 11 Benchmark (L1)',
        Area         = 'Above Lock',
        ResourceType = 'Policy',
        Severity     = 'High',
        Control      = 'cis-intune-win11-l1:1.1',
        Service      = 'Graph',
        License      = 'INTUNE_A',
        Permission   = 'Graph:Scope:DeviceManagementConfiguration.Read.All',
        Author       = 'Pacers31Colts18'
    )]
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        # Where the setting lives: settingsCatalog, compliance or deviceConfiguration.
        [ValidateSet('settingsCatalog', 'compliance', 'deviceConfiguration')]
        [string] $Source = 'settingsCatalog',

        # settingsCatalog only: the platform the policy targets.
        [string] $Platform = 'windows10',

        # The settings catalog setting definition id to check.
        [string] $SettingDefinitionId = 'device_vendor_msft_policy_config_abovelock_allowcortanaabovelock',

        # The value the recommendation requires (the option id for a choice setting).
        [string[]] $Expected = 'device_vendor_msft_policy_config_abovelock_allowcortanaabovelock_0',

        # Only policies whose name matches this wildcard count, such as 'W11-CIS-*'. Empty uses the JLIntune.PolicyNameFilter setting.
        [string] $PolicyNameFilter,

        # Count policies that are not assigned to anything.
        [bool] $IncludeUnassigned = $false,

        # Pass even when a counted policy sets a value that does not meet the requirement.
        [bool] $AllowConflicts = $false
    )

    $Params = @{
        Source              = $Source
        Platform            = $Platform
        SettingDefinitionId = $SettingDefinitionId
        Operator            = 'eq'
        Expected            = $Expected
        PolicyNameFilter    = $PolicyNameFilter
        IncludeUnassigned   = $IncludeUnassigned
        AllowConflicts      = $AllowConflicts
    }

    Test-JlIntuneSetting @Params
}

'@ -replace "`r`n", "`n"

    function Read-Text([string] $Path) { [System.IO.File]::ReadAllText($Path) -replace "`r`n", "`n" }
}

Describe 'New-JLMaesterPack' {
    BeforeAll {
        $script:repo = New-FixtureRepo
        $script:pack = New-FixturePack -Repo $script:repo
        $script:packPath = Join-Path $script:repo 'cis-win11-intune-l1'
    }

    It 'writes a pack that passes Test-JLMaesterPack with no tests yet' {
        { Test-JLMaesterPack -RepoPath $script:repo -InformationAction SilentlyContinue } | Should -Not -Throw
        $script:pack.Code | Should -Be 'JL.CISW11INT.L1'
        $script:pack.Guid | Should -Match '^[0-9a-f-]{36}$'
    }

    It 'writes the manifest, suite and framework file' {
        $manifest = Get-Content (Join-Path $script:packPath 'maester-pack.json') -Raw | ConvertFrom-Json
        $manifest.Id | Should -Be 'pacers31colts18.cis-win11-intune-l1'
        $manifest.Version | Should -Be '0.1.0'
        $manifest.Description | Should -Be 'Checks that Intune policies configure the Level 1 recommendations of the CIS Microsoft Intune for Windows 11 Benchmark v5.0.0. One test per setting.'
        $manifest.Uses.GraphScopes | Should -Be 'DeviceManagementConfiguration.Read.All', 'GroupMember.Read.All'
        $manifest.Banner | Should -Be 'assets/banner.png'
        Test-Path (Join-Path $script:packPath 'assets') -PathType Container | Should -BeTrue
        $suite = Get-Content (Join-Path $script:packPath 'tests/suite.json') -Raw | ConvertFrom-Json
        $suite.Tags | Should -Be 'CIS-Intune', 'L1'
        $suite.Frameworks[0].Key | Should -Be 'cis-intune-win11-l1'
        $framework = Get-Content (Join-Path $script:packPath 'tests/frameworks/cis-intune-win11-l1.json') -Raw | ConvertFrom-Json
        $framework.Name | Should -Be 'CIS Microsoft Intune for Windows 11 Benchmark (Level 1)'
        $framework.Version | Should -Be '5.0.0'
        $framework.Level | Should -Be 'L1'
        $framework.Product | Should -Be 'Intune'
        @($framework.Requirements).Count | Should -Be 0
        Get-ChildItem (Join-Path $script:packPath 'tests') -Filter 'Test.*' | Should -BeNullOrEmpty
        Test-Path (Join-Path $script:packPath 'helpers/Test-JlIntuneSetting.ps1') | Should -BeTrue
    }

    It 'adds the README row and the CHANGELOG section' {
        Read-Text (Join-Path $script:repo 'README.md') | Should -Match ([regex]::Escape('| CIS Windows 11 Intune L1 | [cis-win11-intune-l1](cis-win11-intune-l1/README.md) | `JL.CISW11INT.L1` | CIS Microsoft Intune for Windows 11 Benchmark v5.0.0, Level 1 |'))
        Read-Text (Join-Path $script:repo 'CHANGELOG.md') | Should -Be "# Changelog`n`n## cis-win11-intune-l1 0.1.0`n`nFirst version.`n"
    }

    It 'refuses a reserved tag, an overlapping Code and a framework key in use, and leaves nothing behind' {
        $readme = Read-Text (Join-Path $script:repo 'README.md')
        { New-JLMaesterPack -RepoPath $script:repo -Folder p2 -Code JL.P2 -Name P2 -FrameworkKey p2 -BenchmarkName B -BenchmarkVersion 1.0 -Tags CIS } | Should -Throw '*reserved*'
        { New-JLMaesterPack -RepoPath $script:repo -Folder p2 -Code JL.CISW11INT -Name P2 -FrameworkKey p2 -BenchmarkName B -BenchmarkVersion 1.0 } | Should -Throw '*overlaps*'
        { New-JLMaesterPack -RepoPath $script:repo -Folder p2 -Code JL.P2 -Name P2 -FrameworkKey cis-intune-win11-l1 -BenchmarkName B -BenchmarkVersion 1.0 } | Should -Throw '*already declared*'
        Test-Path (Join-Path $script:repo 'p2') | Should -BeFalse
        Read-Text (Join-Path $script:repo 'README.md') | Should -Be $readme
    }

    It 'writes nothing with -WhatIf' {
        New-JLMaesterPack -RepoPath $script:repo -Folder p3 -Code JL.P3 -Name P3 -FrameworkKey p3 -BenchmarkName B -BenchmarkVersion 1.0 -WhatIf
        Test-Path (Join-Path $script:repo 'p3') | Should -BeFalse
    }
}

Describe 'New-JLMaesterTest' {
    BeforeEach {
        $script:repo = New-FixtureRepo
        $null = New-FixturePack -Repo $script:repo
        $script:packPath = Join-Path $script:repo 'cis-win11-intune-l1'
    }

    It 'writes the settings catalog test file exactly as the template' {
        $out = New-JLMaesterTest -RepoPath $script:repo @script:Cortana
        $out.Id | Should -Be 'MP.JL.CISW11INT.L1.001'
        $out.FunctionName | Should -Be 'Test-JLAbovelockAllowcortanaabovelock'
        Read-Text (Join-Path $script:packPath 'tests/Test.MP.JL.CISW11INT.L1.001.ps1') | Should -BeExactly $script:CortanaPs1
    }

    It 'writes the markdown with the description, what passes, the recommendation and the remediation' {
        $null = New-JLMaesterTest -RepoPath $script:repo @script:Cortana -CspUrl https://learn.microsoft.com/windows/client-management/mdm/policy-csp-abovelock -CspTitle 'Policy CSP - AboveLock'
        $md = Read-Text (Join-Path $script:packPath 'tests/Test.MP.JL.CISW11INT.L1.001.md')
        $md | Should -Match ('^' + [regex]::Escape("#### Description`n`nCortana should not answer"))
        $md | Should -Match ([regex]::Escape('sets **Above Lock > Allow Cortana Above Lock** to **Block**'))
        $md | Should -Match ([regex]::Escape('CIS Microsoft Intune for Windows 11 Benchmark, recommendation 1.1 (Level 1).'))
        $md | Should -Match ([regex]::Escape('2. Add **Above Lock** > **Allow Cortana Above Lock** and set it to **Block**.'))
        $md | Should -Match ([regex]::Escape("#### Related links`n`n- [Policy CSP - AboveLock](https://learn.microsoft.com/windows/client-management/mdm/policy-csp-abovelock)`n`n<!--- Results --->"))
        $md | Should -Not -Match 'Intune - Configuration'
        $md | Should -Match "<!--- Results --->`n%TestResult%`n$"
    }

    It 'leaves out Related links when there is no Microsoft Learn link' {
        $null = New-JLMaesterTest -RepoPath $script:repo @script:Cortana
        $md = Read-Text (Join-Path $script:packPath 'tests/Test.MP.JL.CISW11INT.L1.001.md')
        $md | Should -Not -Match 'Related links'
        $md | Should -Match "devices, and remove any other assigned policy that sets it to something else\.`n`n<!--- Results --->"
        { Test-JLMaesterPack -RepoPath $script:repo -InformationAction SilentlyContinue } | Should -Not -Throw
    }

    It 'opens the Description section with the recommendation without -Description, and the pack still passes every check' {
        $params = $script:Cortana.Clone()
        $params.Remove('Description')
        $null = New-JLMaesterTest -RepoPath $script:repo @params
        $md = Read-Text (Join-Path $script:packPath 'tests/Test.MP.JL.CISW11INT.L1.001.md')
        $md | Should -Match ('^' + [regex]::Escape("#### Description`n`nCIS Microsoft Intune for Windows 11 Benchmark, recommendation 1.1 (Level 1).`n`nThe test passes when"))
        (Get-MtTest -Path $script:packPath | Where-Object Id -EQ 'MP.JL.CISW11INT.L1.001').IsValid | Should -BeTrue
        { Test-JLMaesterPack -RepoPath $script:repo -InformationAction SilentlyContinue } | Should -Not -Throw
    }

    It 'records the requirement, README row and CHANGELOG line, and the pack still passes every check' {
        $null = New-JLMaesterTest -RepoPath $script:repo @script:Cortana
        $framework = Get-Content (Join-Path $script:packPath 'tests/frameworks/cis-intune-win11-l1.json') -Raw | ConvertFrom-Json
        $framework.Requirements[0].Id | Should -Be '1.1'
        $framework.Requirements[0].Level | Should -Be 'L1'
        Read-Text (Join-Path $script:packPath 'README.md') | Should -Match ([regex]::Escape('| MP.JL.CISW11INT.L1.001 | 1.1 | Allow Cortana Above Lock is set to Block | High |'))
        Read-Text (Join-Path $script:repo 'CHANGELOG.md') | Should -Be "# Changelog`n`n## cis-win11-intune-l1 0.1.0`n`nFirst version.`n`n- **MP.JL.CISW11INT.L1.001** Allow Cortana Above Lock is set to Block`n"
        $test = Get-MtTest -Path $script:packPath
        $test.Control | Should -Be 'cis-intune-win11-l1:1.1'
        $test.Benchmark.Requirement | Should -Be '1.1'
        $test.Benchmark.Version | Should -Be '5.0.0'
        { Test-JLMaesterPack -RepoPath $script:repo -InformationAction SilentlyContinue } | Should -Not -Throw
    }

    It 'numbers tests in the order they are added, and keeps requirements in benchmark order' {
        foreach ($rec in '1.10', '1.2', '2.1') {
            $null = New-JLMaesterTest -RepoPath $script:repo @script:Cortana -Recommendation $rec -SettingDisplayName "Setting $rec" -FunctionName "Test-JLSetting$($rec -replace '\.')"
        }
        $rows = @(Get-Content (Join-Path $script:packPath 'README.md') | Where-Object { $_ -like '| MP.*' } | ForEach-Object { ($_ -split '\|')[1].Trim() })
        $rows | Should -Be 'MP.JL.CISW11INT.L1.001', 'MP.JL.CISW11INT.L1.002', 'MP.JL.CISW11INT.L1.003'
        (Get-MtTest -Path $script:packPath | Sort-Object Id).Control | Should -Be 'cis-intune-win11-l1:1.10', 'cis-intune-win11-l1:1.2', 'cis-intune-win11-l1:2.1'
        (Get-Content (Join-Path $script:packPath 'tests/frameworks/cis-intune-win11-l1.json') -Raw | ConvertFrom-Json).Requirements.Id | Should -Be '1.2', '1.10', '2.1'
        # The next number is one more than the highest, whatever the gaps.
        Remove-Item (Join-Path $script:packPath 'tests/Test.MP.JL.CISW11INT.L1.002.*')
        (New-JLMaesterTest -RepoPath $script:repo @script:Cortana -Recommendation 3.1 -FunctionName Test-JLThree -WhatIf).Id | Should -Be 'MP.JL.CISW11INT.L1.004'
    }

    It 'refuses a recommendation that exists and changes nothing' {
        $null = New-JLMaesterTest -RepoPath $script:repo @script:Cortana
        $before = Get-ChildItem $script:repo -Recurse -File | ForEach-Object { "$($_.FullName)|$((Get-FileHash $_.FullName).Hash)" }
        { New-JLMaesterTest -RepoPath $script:repo @script:Cortana } | Should -Throw '*Recommendation 1.1 is already in tests/frameworks/cis-intune-win11-l1.json*'
        Get-ChildItem $script:repo -Recurse -File | ForEach-Object { "$($_.FullName)|$((Get-FileHash $_.FullName).Hash)" } | Should -Be $before
    }

    It 'undoes everything when the run is stopped partway (Ctrl+C), alone or from a CSV' {
        $before = Get-ChildItem $script:repo -Recurse -File | ForEach-Object { "$($_.FullName)|$((Get-FileHash $_.FullName).Hash)" }
        $csv = Join-Path $TestDrive 'stop.csv'
        Set-Content $csv ('Recommendation,SettingDisplayName,ValueDisplayName,SkipReason', '82.7,IIS Admin Service (IISADMIN),Disabled,Set by script')
        $runs = @(
            @{ RepoPath = $script:repo } + $script:Cortana
            @{ RepoPath = $script:repo; Path = $csv; Pack = 'cis-win11-intune-l1'; Severity = 'Medium'; Area = 'System Services' }
        )
        foreach ($run in $runs) {
            # In its own PowerShell, the run pauses after writing the test files; Stop() is what Ctrl+C does.
            $ps = [powershell]::Create()
            $null = $ps.AddScript({
                param($Module, $Run)
                Import-Module Maester -MinimumVersion 3.0.0
                Import-Module $Module -Force
                & (Get-Module JLMaesterTools) { function script:Add-JLChangelogLine { Start-Sleep -Seconds 60 } }
                New-JLMaesterTest @Run
            }).AddArgument((Join-Path $PSScriptRoot '../JLMaesterTools/JLMaesterTools.psd1')).AddArgument($run)
            $async = $ps.BeginInvoke()
            $deadline = (Get-Date).AddSeconds(60)
            while (-not (Test-Path (Join-Path $script:packPath 'tests/Test.MP.JL.CISW11INT.L1.001.md')) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 100 }
            Test-Path (Join-Path $script:packPath 'tests/Test.MP.JL.CISW11INT.L1.001.md') | Should -BeTrue
            $ps.Stop()
            $ps.Dispose()
            Get-ChildItem $script:repo -Recurse -File | ForEach-Object { "$($_.FullName)|$((Get-FileHash $_.FullName).Hash)" } | Should -Be $before
        }
    }

    It 'refuses a function name another test of the pack uses' {
        $null = New-JLMaesterTest -RepoPath $script:repo @script:Cortana
        { New-JLMaesterTest -RepoPath $script:repo @script:Cortana -Recommendation 1.2 } | Should -Throw '*already defines Test-JLAbovelockAllowcortanaabovelock*'
    }

    It 'returns the drafts and writes nothing with -WhatIf' {
        $out = New-JLMaesterTest -RepoPath $script:repo @script:Cortana -WhatIf
        $out.Ps1 + "`n" | Should -BeExactly $script:CortanaPs1
        $out.Markdown | Should -Match 'recommendation 1.1'
        Test-Path (Join-Path $script:packPath 'tests/Test.MP.JL.CISW11INT.L1.001.ps1') | Should -BeFalse
        Read-Text (Join-Path $script:repo 'CHANGELOG.md') | Should -Not -Match 'MP.JL'
    }

    It 'writes a valid compliance test' {
        $out = New-JLMaesterTest -RepoPath $script:repo -Pack cis-win11-intune-l1 -Recommendation 9.1 -Severity Medium -Source compliance `
            -ODataType '#microsoft.graph.windows10CompliancePolicy' -Property bitLockerEnabled -Expected True `
            -SettingDisplayName 'Require BitLocker' -ValueDisplayName Require -Description 'BitLocker protects data at rest.' -Product Intune -Feature 'Device compliance' -Area 'System Security'
        $ps1 = Read-Text (Join-Path $script:packPath "tests/Test.$($out.Id).ps1")
        $ps1 | Should -Match ([regex]::Escape("Feature      = 'Device compliance',"))
        $ps1 | Should -Match ([regex]::Escape('        ODataType           = $ODataType'))
        $ps1 | Should -Match ([regex]::Escape('        Property            = $Property'))
        $ps1 | Should -Not -Match 'SettingDefinitionId'
        { Test-JLMaesterPack -RepoPath $script:repo -InformationAction SilentlyContinue } | Should -Not -Throw
    }

    It 'writes an always-skipped test with -SkipReason, from a CSV row too, and the pack still passes every check' {
        $skip = @{ RepoPath = $script:repo; Pack = 'cis-win11-intune-l1'; Recommendation = '82.7'; Severity = 'Medium'; SettingDisplayName = 'IIS Admin Service (IISADMIN)'; ValueDisplayName = 'Disabled or Not Installed'; Area = 'System Services'; SkipReason = 'Set by script outside the Intune Settings Catalog' }
        $out = New-JLMaesterTest @skip
        $out.Title | Should -Be 'IIS Admin Service (IISADMIN) is set to Disabled or Not Installed'
        $out.FunctionName | Should -Be 'Test-JLIISAdminServiceIISADMIN'
        $ps1 = Read-Text (Join-Path $script:packPath "tests/Test.$($out.Id).ps1")
        $ps1 | Should -Match ([regex]::Escape("Control      = 'cis-intune-win11-l1:82.7',"))
        $ps1 | Should -Match ([regex]::Escape("        [string] `$SkipReason = 'Set by script outside the Intune Settings Catalog'`n    )`n`n    Add-MtTestResultDetail -SkippedBecause Custom -SkippedCustomReason `$SkipReason`n    return `$null`n}"))
        $ps1 | Should -Not -Match 'Test-JlIntuneSetting|SettingDefinitionId'
        $md = Read-Text (Join-Path $script:packPath "tests/Test.$($out.Id).md")
        $md | Should -Match ([regex]::Escape("recommendation 82.7 (Level 1).`n`nThis test is always skipped: Set by script outside the Intune Settings Catalog. Check **IIS Admin Service (IISADMIN)** on the devices"))
        $md | Should -Match ([regex]::Escape('**Devices** > **Scripts and remediations**'))
        { New-JLMaesterTest @skip -Recommendation 82.8 -SettingDefinitionId x -WhatIf } | Should -Throw '*checks no setting; leave out -SettingDefinitionId*'
        { New-JLMaesterTest @skip -Recommendation 82.8 -ValueDisplayName '' -WhatIf } | Should -Throw '*pass -ValueDisplayName*'
        Set-Content (Join-Path $script:repo 'skip.csv') ('Recommendation,SettingDisplayName,ValueDisplayName,SkipReason', '82.8,Infrared monitor service (irmon),Disabled or Not Installed,Set by script')
        (@(New-JLMaesterTest -RepoPath $script:repo -Path (Join-Path $script:repo 'skip.csv') -Pack cis-win11-intune-l1 -Severity Medium -Area 'System Services')).Id | Should -Be 'MP.JL.CISW11INT.L1.002'
        { Test-JLMaesterPack -RepoPath $script:repo -InformationAction SilentlyContinue } | Should -Not -Throw
    }

    It 'words the title and .md for each operator' {
        $cases = @(
            @{ Operator = 'ne'; Title = 'Allow Cortana Above Lock is not set to Allow'; Md = 'to any value other than **Allow**' }
            @{ Operator = 'contains'; Title = 'Allow Cortana Above Lock includes Allow'; Md = 'to a list that includes **Allow**' }
            @{ Operator = 'ge'; Title = 'Allow Cortana Above Lock is at least Allow'; Md = 'to **Allow** or more' }
            @{ Operator = 'le'; Title = 'Allow Cortana Above Lock is at most Allow'; Md = 'to **Allow** or less' }
            @{ Operator = 'in'; Title = 'Allow Cortana Above Lock is set to Allow'; Md = 'to **Allow**,' }
        )
        foreach ($case in $cases) {
            $out = New-JLMaesterTest -RepoPath $script:repo @script:Cortana -Operator $case.Operator -ValueDisplayName Allow -WhatIf
            $out.Title | Should -Be $case.Title
            $out.Markdown | Should -Match ([regex]::Escape($case.Md))
        }
    }

    It 'rewrites a test under its own ID with -Replace, alone or from a CSV, keeping its Severity and Description' {
        $null = New-JLMaesterTest -RepoPath $script:repo @script:Cortana
        $null = New-JLMaesterTest -RepoPath $script:repo @script:Cortana -Recommendation 1.2 -SettingDisplayName 'Setting 1.2' -FunctionName Test-JLSetting12 -Severity Low
        $replace = @{} + $script:Cortana
        $replace.Remove('Severity'); $replace.Remove('Description')
        $out = New-JLMaesterTest -RepoPath $script:repo @replace -Replace -Operator in -Expected 'a_0', 'a_1' -ValueDisplayName 'Block or Allow'
        $out.Id | Should -Be 'MP.JL.CISW11INT.L1.001'
        $out.Replaces | Should -Be 'Allow Cortana Above Lock is set to Block'
        $ps1 = Read-Text (Join-Path $script:packPath 'tests/Test.MP.JL.CISW11INT.L1.001.ps1')
        $ps1 | Should -Match "Severity     = 'High',"
        $ps1 | Should -Match ([regex]::Escape("        Operator            = 'in'"))
        Read-Text (Join-Path $script:packPath 'tests/Test.MP.JL.CISW11INT.L1.001.md') | Should -Match ('^' + [regex]::Escape("#### Description`n`nCortana should not answer"))
        $readme = @(Get-Content (Join-Path $script:packPath 'README.md') | Where-Object { $_ -like '| MP.*' })
        $readme | Should -Be '| MP.JL.CISW11INT.L1.001 | 1.1 | Allow Cortana Above Lock is set to Block or Allow | High |', '| MP.JL.CISW11INT.L1.002 | 1.2 | Setting 1.2 is set to Block | Low |'
        $changelog = @(Get-Content (Join-Path $script:repo 'CHANGELOG.md') | Where-Object { $_ -like '- **MP.*' })
        $changelog | Should -Be '- **MP.JL.CISW11INT.L1.001** Allow Cortana Above Lock is set to Block or Allow', '- **MP.JL.CISW11INT.L1.002** Setting 1.2 is set to Block'
        (Get-Content (Join-Path $script:packPath 'tests/frameworks/cis-intune-win11-l1.json') -Raw | ConvertFrom-Json).Requirements.Id | Should -Be '1.1', '1.2'
        { Test-JLMaesterPack -RepoPath $script:repo -InformationAction SilentlyContinue } | Should -Not -Throw
        { New-JLMaesterTest -RepoPath $script:repo @replace -Recommendation 9.9 -Replace -WhatIf } | Should -Throw '*exactly one test of recommendation 9.9*'
        # From a CSV: the row keeps 002 and its Low severity; a new row takes the next number.
        $csv = Join-Path $script:repo 'replace.csv'
        Set-Content $csv ('Recommendation,Replace,Severity,SettingDefinitionId,Expected,Operator,SettingDisplayName,ValueDisplayName,CategoryPath,Area,FunctionName',
            '1.2,true,,x,x_1,ne,Setting 1.2,Allow,Above Lock,Above Lock,Test-JLSetting12',
            '1.3,,Medium,y,y_0,,Setting 1.3,Block,Above Lock,Above Lock,')
        $rows = @(New-JLMaesterTest -RepoPath $script:repo -Path $csv -Pack cis-win11-intune-l1)
        $rows.Id | Should -Be 'MP.JL.CISW11INT.L1.002', 'MP.JL.CISW11INT.L1.003'
        $rows[0].Replaces | Should -Be 'Setting 1.2 is set to Block'
        Read-Text (Join-Path $script:packPath 'tests/Test.MP.JL.CISW11INT.L1.002.ps1') | Should -Match "Severity     = 'Low',"
        @(Get-Content (Join-Path $script:packPath 'README.md') | Where-Object { $_ -like '| MP.*' }).Count | Should -Be 3
    }

    It 'writes a valid test with several expected values' {
        $out = New-JLMaesterTest -RepoPath $script:repo @script:Cortana -Recommendation 1.3 -FunctionName Test-JLMulti -Operator in -Expected 'a_0', 'a_1' -ValueDisplayName 'Block or Disabled'
        Read-Text (Join-Path $script:packPath "tests/Test.$($out.Id).ps1") | Should -Match ([regex]::Escape("[string[]] `$Expected = ('a_0', 'a_1'),"))
        (Get-MtTest -Path $script:packPath | Where-Object Id -EQ $out.Id).IsValid | Should -BeTrue
    }

    It 'makes Area, Product and Feature optional' {
        $parameters = (Get-Command New-JLMaesterTest).Parameters
        foreach ($name in 'Area', 'Product', 'Feature') {
            $parameters[$name].Attributes.Where({ $_ -is [System.Management.Automation.ParameterAttribute] }).Mandatory | Should -Not -Contain $true
        }
    }

    It 'takes Area from the Intune category path, and lets -Area override it' {
        $noArea = @{} + $script:Cortana
        $noArea.Remove('Area')
        $out = New-JLMaesterTest -RepoPath $script:repo @noArea -CategoryPath 'Administrative Templates > Control Panel > Personalization' -WhatIf
        $out.Area | Should -Be 'Personalization'
        $out.Ps1 | Should -Match ([regex]::Escape("Area         = 'Personalization',"))
        # The .md keeps the whole path.
        $out.Markdown | Should -Match ([regex]::Escape('**Administrative Templates > Control Panel > Personalization > Allow Cortana Above Lock**'))
        (New-JLMaesterTest -RepoPath $script:repo @noArea -WhatIf).Area | Should -Be 'Above Lock'
        (New-JLMaesterTest -RepoPath $script:repo @noArea -CategoryPath 'Administrative Templates > Control Panel' -Area 'My section' -WhatIf).Area | Should -Be 'My section'
    }

    It 'asks for -Area when there is no category path, or it is longer than 60 characters' {
        $noArea = @{} + $script:Cortana
        $noArea.Remove('Area')
        $noArea.Remove('CategoryPath')
        { New-JLMaesterTest -RepoPath $script:repo @noArea -WhatIf } | Should -Throw '*Pass -Area: there is no Intune category path*'
        { New-JLMaesterTest -RepoPath $script:repo @noArea -CategoryPath ('A > ' + 'B' * 61) -WhatIf } | Should -Throw '*Pass -Area:*longer than*60 characters*'
        { New-JLMaesterTest -RepoPath $script:repo -Pack cis-win11-intune-l1 -Recommendation 9.2 -Severity Medium -Source compliance `
            -ODataType '#microsoft.graph.windows10CompliancePolicy' -Property bitLockerEnabled -Expected True `
            -SettingDisplayName 'Require BitLocker' -ValueDisplayName Require -WhatIf } | Should -Throw '*Pass -Area*'
    }

    It 'takes Product from the framework file and Feature from its Name, and lets -Product and -Feature override them' {
        $out = New-JLMaesterTest -RepoPath $script:repo @script:Cortana -WhatIf
        $out.Ps1 | Should -Match ([regex]::Escape("Product      = 'Intune',"))
        $out.Ps1 | Should -Match ([regex]::Escape("Feature      = 'CIS Microsoft Intune for Windows 11 Benchmark (L1)',"))
        $out = New-JLMaesterTest -RepoPath $script:repo @script:Cortana -Product Windows -Feature 'Other benchmark' -WhatIf
        $out.Ps1 | Should -Match ([regex]::Escape("Product      = 'Windows',"))
        $out.Ps1 | Should -Match ([regex]::Escape("Feature      = 'Other benchmark',"))
    }

    It 'stops when the framework file has no Product and -Product is not passed' {
        $path = Join-Path $script:packPath 'tests/frameworks/cis-intune-win11-l1.json'
        $framework = Get-Content $path -Raw | ConvertFrom-Json
        $framework.PSObject.Properties.Remove('Product')
        $framework | ConvertTo-Json -Depth 5 | Set-Content $path
        { New-JLMaesterTest -RepoPath $script:repo @script:Cortana -WhatIf } | Should -Throw '*has no Product*'
        (New-JLMaesterTest -RepoPath $script:repo @script:Cortana -Product Intune -WhatIf).Ps1 | Should -Match "Product      = 'Intune',"
    }

    It 'bumps the minor version once the current version is released' {
        Push-Location $script:repo
        try {
            git init -q -b main; git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init; git tag cis-win11-intune-l1-v0.1.0
        } finally { Pop-Location }
        $out = New-JLMaesterTest -RepoPath $script:repo @script:Cortana
        $out.PackVersion | Should -Be '0.2.0'
        (Get-Content (Join-Path $script:packPath 'maester-pack.json') -Raw | ConvertFrom-Json).Version | Should -Be '0.2.0'
        Read-Text (Join-Path $script:repo 'CHANGELOG.md') | Should -Match "## cis-win11-intune-l1 0.2.0`n`n- \*\*MP.JL.CISW11INT.L1.001\*\*"
    }

    It 'does not bump an unreleased version' {
        (New-JLMaesterTest -RepoPath $script:repo @script:Cortana).PackVersion | Should -Be '0.1.0'
    }
}

Describe 'New-JLMaesterTest -Path' {
    BeforeAll {
        function Get-RepoHash([string] $Repo) { Get-ChildItem $Repo -Recurse -File | ForEach-Object { "$($_.FullName)|$((Get-FileHash $_.FullName).Hash)" } }
        $script:CsvHeader = 'Recommendation,Severity,SettingDefinitionId,Expected,Operator,SettingDisplayName,ValueDisplayName,CategoryPath,Area,Description'
        $script:CsvRows = @(
            '1.1,High,device_vendor_msft_policy_config_abovelock_allowcortanaabovelock,device_vendor_msft_policy_config_abovelock_allowcortanaabovelock_0,,Allow Cortana Above Lock,Block,Above Lock,Above Lock,Cortana should not answer voice requests while the device is locked.'
            '1.2,High,device_vendor_msft_policy_config_abovelock_allowtoasts,device_vendor_msft_policy_config_abovelock_allowtoasts_0,,Allow Toasts,Block,Above Lock,Above Lock,'
            '1.3,Medium,some_setting,a_0; a_1,in,Some Setting,Block or Disabled,Above Lock,Above Lock,'
        )
    }
    BeforeEach {
        $script:repo = New-FixtureRepo
        $null = New-FixturePack -Repo $script:repo
        $script:packPath = Join-Path $script:repo 'cis-win11-intune-l1'
        $script:csv = Join-Path $script:repo 'tests.csv'
    }

    It 'writes a test per row, and the pack passes every check' {
        Set-Content $script:csv (@($script:CsvHeader) + $script:CsvRows)
        $out = @(New-JLMaesterTest -RepoPath $script:repo -Path $script:csv -Pack cis-win11-intune-l1)
        $out.Id | Should -Be 'MP.JL.CISW11INT.L1.001', 'MP.JL.CISW11INT.L1.002', 'MP.JL.CISW11INT.L1.003'
        # The first row writes the same file as a single run.
        Read-Text (Join-Path $script:packPath 'tests/Test.MP.JL.CISW11INT.L1.001.ps1') | Should -BeExactly $script:CortanaPs1
        Read-Text (Join-Path $script:packPath 'tests/Test.MP.JL.CISW11INT.L1.002.md') | Should -Match ('^' + [regex]::Escape("#### Description`n`nCIS Microsoft Intune for Windows 11 Benchmark, recommendation 1.2 (Level 1)."))
        Read-Text (Join-Path $script:packPath 'tests/Test.MP.JL.CISW11INT.L1.003.ps1') | Should -Match ([regex]::Escape("[string[]] `$Expected = ('a_0', 'a_1'),"))
        (Get-Content (Join-Path $script:packPath 'tests/frameworks/cis-intune-win11-l1.json') -Raw | ConvertFrom-Json).Requirements.Id | Should -Be '1.1', '1.2', '1.3'
        @(Get-Content (Join-Path $script:repo 'CHANGELOG.md') | Where-Object { $_ -like '- **MP.*' }).Count | Should -Be 3
        { Test-JLMaesterPack -RepoPath $script:repo -InformationAction SilentlyContinue } | Should -Not -Throw
    }

    It 'numbers the rows on from the tests the pack already has' {
        $null = New-JLMaesterTest -RepoPath $script:repo @script:Cortana
        Set-Content $script:csv (@($script:CsvHeader) + $script:CsvRows[1] + $script:CsvRows[2])
        $out = @(New-JLMaesterTest -RepoPath $script:repo -Path $script:csv -Pack cis-win11-intune-l1 -WhatIf)
        $out.Id | Should -Be 'MP.JL.CISW11INT.L1.002', 'MP.JL.CISW11INT.L1.003'
    }

    It 'returns every draft and writes nothing with -WhatIf' {
        Set-Content $script:csv (@($script:CsvHeader) + $script:CsvRows)
        $before = Get-RepoHash $script:repo
        $out = @(New-JLMaesterTest -RepoPath $script:repo -Path $script:csv -Pack cis-win11-intune-l1 -WhatIf)
        $out.Count | Should -Be 3
        $out[0].Ps1 + "`n" | Should -BeExactly $script:CortanaPs1
        Get-RepoHash $script:repo | Should -Be $before
    }

    It 'writes nothing when a row fails, and names every failing row' {
        Set-Content $script:csv (@($script:CsvHeader) + $script:CsvRows[0] + '1.2,,x,x_0,,X,Block,Above Lock,,' + '1.4,Bad,y,y_0,,Y,Block,,,')
        $before = Get-RepoHash $script:repo
        { New-JLMaesterTest -RepoPath $script:repo -Path $script:csv -Pack cis-win11-intune-l1 } | Should -Throw '*2 of 3 row(s)*nothing was written*Row 3 (1.2): missing Severity*Row 4 (1.4):*'
        Get-RepoHash $script:repo | Should -Be $before
    }

    It 'refuses a recommendation that is in two rows, and an unknown column' {
        Set-Content $script:csv (@($script:CsvHeader) + $script:CsvRows[0] + ($script:CsvRows[1] -replace '^1\.2', '1.1'))
        { New-JLMaesterTest -RepoPath $script:repo -Path $script:csv -Pack cis-win11-intune-l1 } | Should -Throw '*recommendation 1.1 is in rows 2 and 3*'
        Set-Content $script:csv ('Recommendation,Severty', '1.1,High')
        { New-JLMaesterTest -RepoPath $script:repo -Path $script:csv -Pack cis-win11-intune-l1 } | Should -Throw '*not New-JLMaesterTest parameters: Severty*'
    }

    It 'takes Pack from a column and parameters passed with -Path as defaults for every row' {
        Set-Content $script:csv ('Pack,Recommendation,SettingDefinitionId,Expected,SettingDisplayName,ValueDisplayName,Area', 'cis-win11-intune-l1,1.1,a,a_0,Setting A,Block,Above Lock')
        $out = @(New-JLMaesterTest -RepoPath $script:repo -Path $script:csv -Severity Low -WhatIf)
        $out[0].Ps1 | Should -Match "Severity     = 'Low',"
    }
}

Describe 'Find-JLIntuneSetting and New-JLMaesterTest -FromPolicy' {
    BeforeAll {
        Mock Get-MgContext -ModuleName JLMaesterTools { [pscustomobject]@{ TenantId = 'tenant' } }
        Mock Invoke-MgGraphRequest -ModuleName JLMaesterTools {
            switch -Regex ($Uri) {
                '^beta/deviceManagement/configurationPolicies\?' {
                    [pscustomobject]@{ value = @(
                            [pscustomobject]@{ id = 'p1'; name = 'W11_D_CISL1_AboveLock'; platforms = 'windows10' }
                            [pscustomobject]@{ id = 'p2'; name = 'Other'; platforms = 'windows10' }
                            [pscustomobject]@{ id = 'p3'; name = 'W11_D_CISL1_SMB'; platforms = 'windows10' }
                            [pscustomobject]@{ id = 'p4'; name = 'MAC_D_CISL1_Energy'; platforms = 'macOS' }
                        )
                    }
                }
                # macOS Energy Saver: the same settings under each power source, as group settings.
                "^beta/deviceManagement/configurationPolicies\('p4'\)/settings" {
                    $power = {
                        param($Group, $Timer, $Wake)
                        [pscustomobject]@{
                            settingInstance    = [pscustomobject]@{
                                '@odata.type'               = '#microsoft.graph.deviceManagementConfigurationGroupSettingInstance'
                                settingDefinitionId         = "mcx_$Group"
                                groupSettingValue           = [pscustomobject]@{ children = @(
                                        [pscustomobject]@{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSimpleSettingInstance'; settingDefinitionId = "mcx_$($Group)_display sleep timer"; simpleSettingValue = [pscustomobject]@{ value = $Timer } }
                                        [pscustomobject]@{ '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'; settingDefinitionId = "mcx_$($Group)_wake on lan"; choiceSettingValue = [pscustomobject]@{ value = "mcx_$($Group)_wake on lan_$Wake"; children = @() } }
                                    ) }
                            }
                            settingDefinitions = @(
                                [pscustomobject]@{ id = "mcx_$Group"; displayName = $Group; categoryId = $Group }
                                [pscustomobject]@{ id = "mcx_$($Group)_display sleep timer"; displayName = 'Display Sleep Timer'; categoryId = $Group }
                                [pscustomobject]@{ id = "mcx_$($Group)_wake on lan"; displayName = 'Wake on LAN'; categoryId = $Group; options = @(
                                        [pscustomobject]@{ itemId = "mcx_$($Group)_wake on lan_0"; displayName = 'False' }
                                        [pscustomobject]@{ itemId = "mcx_$($Group)_wake on lan_1"; displayName = 'True' }) }
                            )
                        }
                    }
                    [pscustomobject]@{ value = @((& $power desktop 10 0), (& $power battery 5 0)) }
                }
                "^beta/deviceManagement/configurationCategories\('desktop'\)$" { [pscustomobject]@{ id = 'desktop'; displayName = 'Desktop Power'; parentCategoryId = 'energy' } }
                "^beta/deviceManagement/configurationCategories\('battery'\)$" { [pscustomobject]@{ id = 'battery'; displayName = 'Laptop Battery Power'; parentCategoryId = 'energy' } }
                "^beta/deviceManagement/configurationCategories\('energy'\)$" { [pscustomobject]@{ id = 'energy'; displayName = 'Energy Saver'; parentCategoryId = '00000000-0000-0000-0000-000000000000' } }
                "^beta/deviceManagement/configurationPolicies\('p1'\)/settings" {
                    [pscustomobject]@{ value = @([pscustomobject]@{
                                settingInstance    = [pscustomobject]@{
                                    '@odata.type'       = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'
                                    settingDefinitionId = 'device_vendor_msft_policy_config_abovelock_allowcortanaabovelock'
                                    choiceSettingValue  = [pscustomobject]@{ value = 'device_vendor_msft_policy_config_abovelock_allowcortanaabovelock_0'; children = @() }
                                }
                                settingDefinitions = @([pscustomobject]@{
                                        id          = 'device_vendor_msft_policy_config_abovelock_allowcortanaabovelock'
                                        displayName = 'Allow Cortana Above Lock'
                                        categoryId  = 'cat1'
                                        infoUrls    = @('https://learn.microsoft.com/windows/client-management/mdm/policy-csp-abovelock')
                                        options     = @(
                                            [pscustomobject]@{ itemId = 'device_vendor_msft_policy_config_abovelock_allowcortanaabovelock_0'; displayName = 'Block' }
                                            [pscustomobject]@{ itemId = 'device_vendor_msft_policy_config_abovelock_allowcortanaabovelock_1'; displayName = 'Allow' }
                                        )
                                    })
                            })
                    }
                }
                # As the tenant returns them: Above Lock is its own root; Personalization is under Control Panel under
                # the Administrative Templates root.
                # An Administrative Templates setting with a child under Enabled, as the SMB v1 client driver one.
                "^beta/deviceManagement/configurationPolicies\('p3'\)/settings" {
                    [pscustomobject]@{ value = @([pscustomobject]@{
                                settingInstance    = [pscustomobject]@{
                                    '@odata.type'       = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'
                                    settingDefinitionId = 'smb'
                                    choiceSettingValue  = [pscustomobject]@{ value = 'smb_1'; children = @(
                                            [pscustomobject]@{
                                                '@odata.type'       = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'
                                                settingDefinitionId = 'smb_driver'
                                                choiceSettingValue  = [pscustomobject]@{ value = 'smb_driver_4'; children = @() }
                                            }) }
                                }
                                settingDefinitions = @(
                                    [pscustomobject]@{ id = 'smb'; displayName = 'Configure SMB v1 client driver'; categoryId = 'pers'; options = @(
                                            [pscustomobject]@{ itemId = 'smb_0'; displayName = 'Disabled' }
                                            [pscustomobject]@{ itemId = 'smb_1'; displayName = 'Enabled' }) }
                                    [pscustomobject]@{ id = 'smb_driver'; displayName = 'Configure MrxSmb10 driver'; categoryId = 'pers'; options = @(
                                            [pscustomobject]@{ itemId = 'smb_driver_2'; displayName = 'Manual start (default)' }
                                            [pscustomobject]@{ itemId = 'smb_driver_4'; displayName = 'Disable driver (recommended)' }) }
                                )
                            }
                            # A parent with two children that the benchmark numbers separately, as Configure RPC connection settings.
                            [pscustomobject]@{
                                settingInstance    = [pscustomobject]@{
                                    '@odata.type'       = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'
                                    settingDefinitionId = 'rpc'
                                    choiceSettingValue  = [pscustomobject]@{ value = 'rpc_1'; children = @(
                                            [pscustomobject]@{
                                                '@odata.type'       = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'
                                                settingDefinitionId = 'rpc_protocol'
                                                choiceSettingValue  = [pscustomobject]@{ value = 'rpc_protocol_0'; children = @() }
                                            }
                                            [pscustomobject]@{
                                                '@odata.type'       = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'
                                                settingDefinitionId = 'rpc_auth'
                                                choiceSettingValue  = [pscustomobject]@{ value = 'rpc_auth_0'; children = @() }
                                            }) }
                                }
                                settingDefinitions = @(
                                    [pscustomobject]@{ id = 'rpc'; displayName = 'Configure RPC connection settings'; categoryId = 'pers'; options = @(
                                            [pscustomobject]@{ itemId = 'rpc_0'; displayName = 'Disabled' }
                                            [pscustomobject]@{ itemId = 'rpc_1'; displayName = 'Enabled' }) }
                                    [pscustomobject]@{ id = 'rpc_protocol'; displayName = 'Protocol to use for outgoing RPC connections:'; categoryId = 'pers'; options = @(
                                            [pscustomobject]@{ itemId = 'rpc_protocol_0'; displayName = 'RPC over TCP' }
                                            [pscustomobject]@{ itemId = 'rpc_protocol_1'; displayName = 'RPC over named pipes' }) }
                                    [pscustomobject]@{ id = 'rpc_auth'; displayName = 'Use authentication for outgoing RPC connections:'; categoryId = 'pers'; options = @(
                                            [pscustomobject]@{ itemId = 'rpc_auth_0'; displayName = 'Default' }
                                            [pscustomobject]@{ itemId = 'rpc_auth_1'; displayName = 'Authentication enabled' }) }
                                )
                            }
                            # A parent whose child is a list, as Prevent installation of devices using drivers that match
                            # these device setup classes: one row holds every value of the list.
                            [pscustomobject]@{
                                settingInstance    = [pscustomobject]@{
                                    '@odata.type'       = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'
                                    settingDefinitionId = 'dev'
                                    choiceSettingValue  = [pscustomobject]@{ value = 'dev_1'; children = @(
                                            [pscustomobject]@{
                                                '@odata.type'                = '#microsoft.graph.deviceManagementConfigurationSimpleSettingCollectionInstance'
                                                settingDefinitionId          = 'dev_list'
                                                simpleSettingCollectionValue = @([pscustomobject]@{ value = '{class-a}' }, [pscustomobject]@{ value = '{class-b}' })
                                            }) }
                                }
                                settingDefinitions = @(
                                    [pscustomobject]@{ id = 'dev'; displayName = 'Prevent installation of devices using drivers that match these device setup classes'; categoryId = 'pers'; options = @(
                                            [pscustomobject]@{ itemId = 'dev_0'; displayName = 'Disabled' }
                                            [pscustomobject]@{ itemId = 'dev_1'; displayName = 'Enabled' }) }
                                    [pscustomobject]@{ id = 'dev_list'; displayName = 'Prevented Classes'; categoryId = 'pers' }
                                )
                            }
                            # A user right: several accounts.
                            [pscustomobject]@{
                                settingInstance    = [pscustomobject]@{
                                    '@odata.type'                 = '#microsoft.graph.deviceManagementConfigurationSimpleSettingCollectionInstance'
                                    settingDefinitionId           = 'ur_network'
                                    simpleSettingCollectionValue  = @([pscustomobject]@{ value = '*S-1-5-32-544' }, [pscustomobject]@{ value = '*S-1-5-32-555' })
                                }
                                settingDefinitions = @([pscustomobject]@{ id = 'ur_network'; displayName = 'Access From Network '; categoryId = 'pers' })
                            })
                    }
                }
                "^beta/deviceManagement/configurationCategories\('cat1'\)$" { [pscustomobject]@{ id = 'cat1'; displayName = 'Above Lock'; parentCategoryId = '00000000-0000-0000-0000-000000000000'; rootCategoryId = 'cat1' } }
                "^beta/deviceManagement/configurationCategories\('pers'\)$" { [pscustomobject]@{ id = 'pers'; displayName = 'Personalization'; parentCategoryId = 'cp'; rootCategoryId = 'admx' } }
                "^beta/deviceManagement/configurationCategories\('cp'\)$" { [pscustomobject]@{ id = 'cp'; displayName = 'Control Panel'; parentCategoryId = 'admx'; rootCategoryId = 'admx' } }
                "^beta/deviceManagement/configurationCategories\('admx'\)$" { [pscustomobject]@{ id = 'admx'; displayName = 'Administrative Templates'; parentCategoryId = '00000000-0000-0000-0000-000000000000'; rootCategoryId = 'admx' } }
                default { throw "Unexpected Graph call: $Uri" }
            }
        }
    }

    It 'finds the setting with its value, labels, category and options' {
        $hit = @(Find-JLIntuneSetting -PolicyName 'W11_D_CISL1_*' -Name 'Allow Cortana*')
        $hit.Count | Should -Be 1
        $hit[0].SettingDefinitionId | Should -Be 'device_vendor_msft_policy_config_abovelock_allowcortanaabovelock'
        $hit[0].ValueDisplayName | Should -Be 'Block'
        $hit[0].CategoryPath | Should -Be 'Above Lock'
        $hit[0].Options.DisplayName | Should -Be 'Block', 'Allow'
        $hit[0].Platform | Should -Be 'windows10'
    }

    It 'includes the root category in the path' {
        InModuleScope JLMaesterTools {
            $script:JLCategoryCache = $null
            Get-JLCategoryPath -CategoryId pers | Should -Be 'Administrative Templates > Control Panel > Personalization'
            Get-JLCategoryPath -CategoryId cat1 | Should -Be 'Above Lock'
        }
    }

    It 'warns and returns nothing when no policy matches' {
        Find-JLIntuneSetting -PolicyName 'Nope' -WarningVariable w -WarningAction SilentlyContinue | Should -BeNullOrEmpty
        $w | Should -Match 'No settings catalog policy'
    }

    It 'fills the test from the policy and writes the same file as the manual parameters' {
        $repo = New-FixtureRepo
        $null = New-FixturePack -Repo $repo
        $out = New-JLMaesterTest -RepoPath $repo -Pack cis-win11-intune-l1 -Recommendation 1.1 -Severity High -FromPolicy 'W11_D_CISL1_*' -SettingDisplayName 'Allow Cortana*' -Description 'Cortana should not answer voice requests while the device is locked.' -Product Intune -Feature 'CIS Microsoft Intune for Windows 11 Benchmark (L1)' -Area 'Above Lock'
        $out.Title | Should -Be 'Allow Cortana Above Lock is set to Block'
        Read-Text (Join-Path $repo 'cis-win11-intune-l1/tests/Test.MP.JL.CISW11INT.L1.001.ps1') | Should -BeExactly $script:CortanaPs1
        Read-Text (Join-Path $repo 'cis-win11-intune-l1/tests/Test.MP.JL.CISW11INT.L1.001.md') | Should -Match ([regex]::Escape('- [Microsoft Learn](https://learn.microsoft.com/windows/client-management/mdm/policy-csp-abovelock)'))
    }

    It 'checks the children the policy configures under the setting' {
        $repo = New-FixtureRepo
        $null = New-FixturePack -Repo $repo
        $out = New-JLMaesterTest -RepoPath $repo -Pack cis-win11-intune-l1 -Recommendation 4.4.2 -Severity High -FromPolicy 'W11_D_CISL1_*' -SettingDisplayName 'Configure SMB v1 client driver' -ValueDisplayName Enabled -Area 'MS Security Guide'
        $out.Title | Should -Be 'Configure SMB v1 client driver is set to Enabled: Disable driver (recommended)'
        $out.Children.SettingDefinitionId | Should -Be 'smb_driver'
        $ps1 = Read-Text (Join-Path $repo 'cis-win11-intune-l1/tests/Test.MP.JL.CISW11INT.L1.001.ps1')
        $ps1 | Should -Match ([regex]::Escape("[string[]] `$ChildSettingDefinitionId = 'smb_driver',"))
        $ps1 | Should -Match ([regex]::Escape("[string[]] `$ChildExpected = 'smb_driver_4',"))
        $ps1 | Should -Match ([regex]::Escape('        SettingDefinitionId      = $SettingDefinitionId'))
        $ps1 | Should -Match ([regex]::Escape('        ChildSettingDefinitionId = $ChildSettingDefinitionId'))
        $md = Read-Text (Join-Path $repo 'cis-win11-intune-l1/tests/Test.MP.JL.CISW11INT.L1.001.md')
        $md | Should -Match ([regex]::Escape('to **Enabled**, with **Configure MrxSmb10 driver** set to **Disable driver (recommended)** in the same policy, and no other'))
        $md | Should -Match ([regex]::Escape('and set it to **Enabled**, then set **Configure MrxSmb10 driver** to **Disable driver (recommended)**.'))
        $test = Get-MtTest -Path (Join-Path $repo 'cis-win11-intune-l1') | Where-Object Id -EQ 'MP.JL.CISW11INT.L1.001'
        $test.IsValid | Should -BeTrue
        @($test.Parameters.Name) | Should -Contain 'ChildExpected'
        { Test-JLMaesterPack -RepoPath $repo -InformationAction SilentlyContinue } | Should -Not -Throw
    }

    It 'checks only the setting with -NoChildren, and refuses child parameters that do not pair up' {
        $repo = New-FixtureRepo
        $null = New-FixturePack -Repo $repo
        $common = @{ RepoPath = $repo; Pack = 'cis-win11-intune-l1'; Recommendation = '4.4.2'; Severity = 'High'; Area = 'MS Security Guide'; WhatIf = $true }
        $out = New-JLMaesterTest @common -FromPolicy 'W11_D_CISL1_*' -SettingDisplayName 'Configure SMB v1 client driver' -ValueDisplayName Enabled -NoChildren
        $out.Title | Should -Be 'Configure SMB v1 client driver is set to Enabled'
        $out.Ps1 | Should -Not -Match 'Child'
        { New-JLMaesterTest @common -SettingDefinitionId smb -Expected smb_1 -SettingDisplayName 'Configure SMB v1 client driver' -ValueDisplayName Enabled -ChildSettingDefinitionId smb_driver -ChildExpected smb_driver_4 } | Should -Throw '*pass one of each per child setting*'
    }

    It 'checks only the children -ChildSettingDefinitionId picks, with names and values from the policy' {
        $repo = New-FixtureRepo
        $null = New-FixturePack -Repo $repo
        # Ids only: the names, values and category all come from the policy.
        $common = @{ RepoPath = $repo; Pack = 'cis-win11-intune-l1'; Severity = 'High'; FromPolicy = 'W11_D_CISL1_*'; SettingDefinitionId = 'rpc'; WhatIf = $true }
        $out = New-JLMaesterTest @common -Recommendation 4.7.3 -ChildSettingDefinitionId rpc_protocol
        $out.Title | Should -Be 'Configure RPC connection settings: Protocol to use for outgoing RPC connections is set to Enabled: RPC over TCP'
        $out.FunctionName | Should -Be 'Test-JLRpcProtocol'
        $out.Markdown | Should -Match ([regex]::Escape('with **Protocol to use for outgoing RPC connections** set to **RPC over TCP** in the same policy'))
        $out.Children.SettingDefinitionId | Should -Be 'rpc_protocol'
        $out.Ps1 | Should -Not -Match 'rpc_auth'
        # Without -ChildSettingDefinitionId every child is checked, as before.
        (New-JLMaesterTest @common -Recommendation 4.7.3).Children.SettingDefinitionId | Should -Be 'rpc_protocol', 'rpc_auth'
        { New-JLMaesterTest @common -Recommendation 4.7.3 -ChildSettingDefinitionId nope } | Should -Throw "*'nope' is not one of the children*rpc_protocol (Protocol to use for outgoing RPC connections), rpc_auth (Use authentication for outgoing RPC connections)*"
        # Names given with picked children replace the policy's; without picked children they are refused.
        (New-JLMaesterTest @common -Recommendation 4.7.3 -ChildSettingDefinitionId rpc_protocol -ChildValueDisplayName 'TCP').Title | Should -Be 'Configure RPC connection settings: Protocol to use for outgoing RPC connections is set to Enabled: TCP'
        { New-JLMaesterTest @common -Recommendation 4.7.3 -ChildValueDisplayName 'TCP' } | Should -Throw '*pass -ChildSettingDefinitionId too*'
        { New-JLMaesterTest @common -Recommendation 4.7.3 -ChildSettingDefinitionId rpc_protocol -ChildValueDisplayName 'a', 'b' } | Should -Throw '*one per picked child*'
        # -ChildExpected replaces the policy's value; the child stays picked (named in the title and function), and the
        # policy must still configure it.
        $out = New-JLMaesterTest @common -Recommendation 4.7.3 -ChildSettingDefinitionId rpc_protocol -ChildExpected rpc_protocol_1 -ChildDisplayName 'Protocol' -ChildValueDisplayName 'RPC over named pipes'
        $out.Children.Expected | Should -Be 'rpc_protocol_1'
        $out.Title | Should -Be 'Configure RPC connection settings: Protocol is set to Enabled: RPC over named pipes'
        $out.FunctionName | Should -Be 'Test-JLRpcProtocol'
        { New-JLMaesterTest @common -Recommendation 4.7.3 -ChildSettingDefinitionId nope -ChildExpected nope_1 -ChildDisplayName 'Nope' -ChildValueDisplayName 'One' } | Should -Throw "*'nope' is not one of the children*"
        { New-JLMaesterTest @common -Recommendation 4.7.3 -ChildExpected rpc_protocol_1 } | Should -Throw '*pass -ChildSettingDefinitionId too*'
    }

    It 'checks a picked list child with -ChildExpected, and refuses one without it' {
        $common = @{ RepoPath = (New-FixtureRepo); Pack = 'cis-win11-intune-l1'; Severity = 'High'; FromPolicy = 'W11_D_CISL1_*'; SettingDefinitionId = 'dev'; Recommendation = '4.10.9.1.3'; WhatIf = $true }
        $null = New-FixturePack -Repo $common.RepoPath
        $out = New-JLMaesterTest @common -ChildSettingDefinitionId dev_list -ChildOperator contains -ChildExpected '{class-a}|{class-b}' -ChildValueDisplayName 'Classes A and B'
        $out.Children.SettingDefinitionId | Should -Be 'dev_list'
        $out.Children.Expected | Should -Be '{class-a}|{class-b}'
        $out.Title | Should -Be 'Prevent installation of devices using drivers that match these device setup classes: Prevented Classes is set to Enabled: Classes A and B'
        $out.Ps1 | Should -Match ([regex]::Escape("[string[]] `$ChildExpected = '{class-a}|{class-b}',"))
        $out.Ps1 | Should -Match ([regex]::Escape("[string[]] `$ChildOperator = 'contains',"))
        { New-JLMaesterTest @common -ChildSettingDefinitionId dev_list } | Should -Throw "*'Prevented Classes' has 2 values; pick it with -ChildSettingDefinitionId and pass -ChildExpected*"
        { New-JLMaesterTest @common } | Should -Throw "*'Prevented Classes' has 2 values*"
    }

    It 'escapes Markdown in the names and values the .md shows, so \\*\NETLOGON shows as written' {
        $repo = New-FixtureRepo
        $null = New-FixturePack -Repo $repo
        $out = New-JLMaesterTest -RepoPath $repo -Pack cis-win11-intune-l1 -Recommendation 4.6.11.1 -Severity High -SettingDefinitionId unc -Expected unc_1 `
            -SettingDisplayName 'Hardened UNC Paths' -ValueDisplayName Enabled -CategoryPath 'Network Provider' -ChildSettingDefinitionId unc_key `
            -ChildOperator contains -ChildExpected '\\*\NETLOGON|\\*\SYSVOL' -ChildDisplayName Name -ChildValueDisplayName '\\*\NETLOGON and \\*\SYSVOL' -WhatIf
        $out.Markdown | Should -Match ([regex]::Escape('**Name** set to **\\\\\*\\NETLOGON and \\\\\*\\SYSVOL**'))
        # The test file keeps the values as they are.
        $out.Ps1 | Should -Match ([regex]::Escape("[string[]] `$ChildExpected = '\\*\NETLOGON|\\*\SYSVOL',"))
    }

    It 'compares a picked child with -ChildOperator: in by hand, exists with no value from the policy' {
        $repo = New-FixtureRepo
        $null = New-FixturePack -Repo $repo
        $common = @{ RepoPath = $repo; Pack = 'cis-win11-intune-l1'; Severity = 'High'; FromPolicy = 'W11_D_CISL1_*'; SettingDefinitionId = 'rpc' }
        $out = New-JLMaesterTest @common -Recommendation 4.7.3 -ChildSettingDefinitionId rpc_protocol -ChildOperator in -ChildExpected 'rpc_protocol_0|rpc_protocol_1' -ChildDisplayName 'Protocol' -ChildValueDisplayName 'TCP or named pipes'
        $out.Title | Should -Be 'Configure RPC connection settings: Protocol is set to Enabled: TCP or named pipes'
        $ps1 = Read-Text (Join-Path $repo "cis-win11-intune-l1/tests/Test.$($out.Id).ps1")
        $ps1 | Should -Match ([regex]::Escape("[string[]] `$ChildExpected = 'rpc_protocol_0|rpc_protocol_1',"))
        $ps1 | Should -Match ([regex]::Escape("[string[]] `$ChildOperator = 'in',"))
        $ps1 | Should -Match ([regex]::Escape('        ChildOperator            = $ChildOperator'))
        # exists: the policy's value stays out of the test, and the title says any value unless named.
        $out = New-JLMaesterTest @common -Recommendation 4.7.4 -ChildSettingDefinitionId rpc_auth -ChildOperator exists -FunctionName Test-JLRpcAuthAny
        $out.Title | Should -Be 'Configure RPC connection settings: Use authentication for outgoing RPC connections is set to Enabled: any value'
        $ps1 = Read-Text (Join-Path $repo "cis-win11-intune-l1/tests/Test.$($out.Id).ps1")
        $ps1 | Should -Match ([regex]::Escape("[string[]] `$ChildExpected = '',"))
        $ps1 | Should -Not -Match 'rpc_auth_0'
        (Get-MtTest -Path (Join-Path $repo 'cis-win11-intune-l1')).IsValid | Should -Not -Contain $false
        { Test-JLMaesterPack -RepoPath $repo -InformationAction SilentlyContinue } | Should -Not -Throw
        { New-JLMaesterTest @common -Recommendation 4.7.5 -ChildSettingDefinitionId rpc_auth -ChildOperator ge, eq -WhatIf } | Should -Throw '*one operator per child setting*'
    }

    It 'names the function after the setting definition id' {
        InModuleScope JLMaesterTools {
            ConvertTo-JLPascalCase -Text 'admx_eventlog_channel_log_retention_2' | Should -Be 'AdmxEventlogChannelLogRetention2'
        }
        $repo = New-FixtureRepo
        $null = New-FixturePack -Repo $repo
        $common = @{ RepoPath = $repo; Pack = 'cis-win11-intune-l1'; Severity = 'High'; Expected = 'x_1'; ValueDisplayName = 'Enabled'; CategoryPath = 'Event Log Service > Security'; WhatIf = $true }
        (New-JLMaesterTest @common -Recommendation 9.1 -SettingDefinitionId device_vendor_msft_policy_config_admx_eventlog_channel_log_retention_2 -SettingDisplayName 'Control Event Log behavior').FunctionName | Should -Be 'Test-JLAdmxEventlogChannelLogRetention2'
        (New-JLMaesterTest @common -Recommendation 9.2 -SettingDefinitionId user_vendor_msft_policy_config_experience_allowspotlightcollection -SettingDisplayName 'Allow Spotlight Collection (User)').FunctionName | Should -Be 'Test-JLUserExperienceAllowspotlightcollection'
        (New-JLMaesterTest @common -Recommendation 9.3 -SettingDefinitionId vendor_msft_firewall_mdmstore_privateprofile_enablefirewall -SettingDisplayName 'Enable Private Network Firewall').FunctionName | Should -Be 'Test-JLFirewallMdmstorePrivateprofileEnablefirewall'
        (New-JLMaesterTest @common -Recommendation 9.4 -SettingDefinitionId device_vendor_msft_laps_policies_backupdirectory -SettingDisplayName 'Backup Directory').FunctionName | Should -Be 'Test-JLLapsPoliciesBackupdirectory'
        $compliance = @{ RepoPath = $repo; Pack = 'cis-win11-intune-l1'; Severity = 'High'; Source = 'compliance'; ODataType = '#microsoft.graph.windows10CompliancePolicy'; Property = 'bitLockerEnabled'; Expected = 'True'; SettingDisplayName = 'Require BitLocker'; ValueDisplayName = 'Require'; Area = 'Device Health'; WhatIf = $true }
        (New-JLMaesterTest @compliance -Recommendation 9.5).FunctionName | Should -Be 'Test-JLWindows10CompliancePolicyBitLockerEnabled'
        # -FunctionName still overrides it.
        (New-JLMaesterTest @common -Recommendation 9.6 -SettingDefinitionId a_b -SettingDisplayName 'A B' -FunctionName Test-JLMine).FunctionName | Should -Be 'Test-JLMine'
    }

    It 'checks a setting with several values with in' {
        $repo = New-FixtureRepo
        $null = New-FixturePack -Repo $repo
        $out = New-JLMaesterTest -RepoPath $repo -Pack cis-win11-intune-l1 -Recommendation 90.2 -Severity High -FromPolicy 'W11_D_CISL1_*' -SettingDefinitionId ur_network
        $out.Expected | Should -Be '*S-1-5-32-544', '*S-1-5-32-555'
        # Intune's name ends in a space; the title and .md leave it out.
        $out.Title | Should -BeLike 'Access From Network is set to *'
        $out.Markdown | Should -Match ([regex]::Escape('> Personalization > Access From Network** to'))
        $ps1 = Read-Text (Join-Path $repo 'cis-win11-intune-l1/tests/Test.MP.JL.CISW11INT.L1.001.ps1')
        $ps1 | Should -Match "Operator\s+= 'in'"
        $ps1 | Should -Match ([regex]::Escape("[string[]] `$Expected = ('*S-1-5-32-544', '*S-1-5-32-555'),"))
        { Test-JLMaesterPack -RepoPath $repo -InformationAction SilentlyContinue } | Should -Not -Throw
        # An -Operator passed is kept.
        { New-JLMaesterTest -RepoPath $repo -Pack cis-win11-intune-l1 -Recommendation 90.3 -Severity High -FromPolicy 'W11_D_CISL1_*' -SettingDefinitionId ur_network -Operator eq -WhatIf } | Should -Throw '*Operator eq takes one expected value*'
    }

    It 'leaves the policy''s value out of an exists test' {
        $repo = New-FixtureRepo
        $null = New-FixturePack -Repo $repo
        $out = New-JLMaesterTest -RepoPath $repo -Pack cis-win11-intune-l1 -Recommendation 49.9 -Severity High -FromPolicy 'W11_D_CISL1_*' -SettingDefinitionId device_vendor_msft_policy_config_abovelock_allowcortanaabovelock -Operator exists -Area 'Above Lock'
        $out.Title | Should -Be 'Allow Cortana Above Lock is configured'
        $out.Expected | Should -BeNullOrEmpty
        $ps1 = Read-Text (Join-Path $repo "cis-win11-intune-l1/tests/Test.$($out.Id).ps1")
        $ps1 | Should -Match ([regex]::Escape('        [string[]] $Expected,'))
        $ps1 | Should -Match "Operator\s+= 'exists'"
        $ps1 | Should -Not -Match 'allowcortanaabovelock_0'
        $md = Read-Text (Join-Path $repo "cis-win11-intune-l1/tests/Test.$($out.Id).md")
        $md | Should -Match ([regex]::Escape('sets **Above Lock > Allow Cortana Above Lock** to any value'))
        $md | Should -Not -Match 'Block'
        { Test-JLMaesterPack -RepoPath $repo -InformationAction SilentlyContinue } | Should -Not -Throw
    }

    It 'writes one test per child of the same parent from a CSV' {
        $repo = New-FixtureRepo
        $null = New-FixturePack -Repo $repo
        $csv = Join-Path $repo 'tests.csv'
        Set-Content $csv ('Recommendation,FromPolicy,SettingDefinitionId,ChildSettingDefinitionId',
            '4.7.3,W11_D_CISL1_*,rpc,rpc_protocol',
            '4.7.4,W11_D_CISL1_*,rpc,rpc_auth')
        $out = @(New-JLMaesterTest -RepoPath $repo -Path $csv -Pack cis-win11-intune-l1 -Severity High)
        $out.Title | Should -Be 'Configure RPC connection settings: Protocol to use for outgoing RPC connections is set to Enabled: RPC over TCP',
            'Configure RPC connection settings: Use authentication for outgoing RPC connections is set to Enabled: Default'
        $out.Children | Should -Be 'Protocol to use for outgoing RPC connections = RPC over TCP', 'Use authentication for outgoing RPC connections = Default'
        { Test-JLMaesterPack -RepoPath $repo -InformationAction SilentlyContinue } | Should -Not -Throw
    }

    It 'reads children from the policy for a CSV row' {
        $repo = New-FixtureRepo
        $null = New-FixturePack -Repo $repo
        $csv = Join-Path $repo 'tests.csv'
        Set-Content $csv ('Recommendation,Severity,FromPolicy,SettingDisplayName,ValueDisplayName', '4.4.2,High,W11_D_CISL1_*,Configure SMB v1 client driver,Enabled')
        $out = @(New-JLMaesterTest -RepoPath $repo -Path $csv -Pack cis-win11-intune-l1)
        $out[0].Title | Should -Be 'Configure SMB v1 client driver is set to Enabled: Disable driver (recommended)'
        # No Area column: it comes from the setting's category in the tenant.
        $out[0].Area | Should -Be 'Personalization'
        Read-Text (Join-Path $repo 'cis-win11-intune-l1/tests/Test.MP.JL.CISW11INT.L1.001.ps1') | Should -Match ([regex]::Escape("Area         = 'Personalization',"))
        $out[0].Children | Should -Be 'Configure MrxSmb10 driver = Disable driver (recommended)'
        Test-Path (Join-Path $repo 'cis-win11-intune-l1/tests/Test.MP.JL.CISW11INT.L1.001.ps1') | Should -BeTrue
    }

    It 'writes a CSV of the policies, which New-JLMaesterTest -Path takes once the Recommendations are filled in' {
        $repo = New-FixtureRepo
        $null = New-FixturePack -Repo $repo
        $csv = Join-Path $repo 'export.csv'
        $result = Export-JLMaesterTestCsv -PolicyName 'W11_D_CISL1_*' -Path $csv -RepoPath $repo
        $result.Rows | Should -Be 9
        $rows = @(Import-Csv $csv)
        $rows[0].PSObject.Properties.Name | Should -Be 'Recommendation', 'Severity', 'FromPolicy', 'SettingDefinitionId', 'SettingDisplayName', 'Operator', 'Expected', 'ValueDisplayName', 'NoChildren',
        'ChildSettingDefinitionId', 'ChildDisplayName', 'ChildOperator', 'ChildExpected', 'ChildValueDisplayName'
        $key = { param($r) "$($r.SettingDefinitionId)|$($r.ChildSettingDefinitionId)" }
        @($rows | ForEach-Object { & $key $_ }) | Should -Be 'device_vendor_msft_policy_config_abovelock_allowcortanaabovelock|', 'smb|', 'smb|smb_driver',
        'rpc|', 'rpc|rpc_protocol', 'rpc|rpc_auth', 'dev|', 'dev|dev_list', 'ur_network|'
        $row = { param($k) $rows | Where-Object { (& $key $_) -eq $k } }
        $above = & $row 'device_vendor_msft_policy_config_abovelock_allowcortanaabovelock|'
        $above.Expected | Should -Be 'device_vendor_msft_policy_config_abovelock_allowcortanaabovelock_0'
        $above.ValueDisplayName | Should -Be 'Block'
        $above.FromPolicy | Should -Be 'W11_D_CISL1_*'
        $above.Recommendation | Should -BeNullOrEmpty
        # A setting with children: the setting alone, and one row per child with its name and value.
        (& $row 'smb|').NoChildren | Should -Be 'true'
        (& $row 'smb|smb_driver').ChildDisplayName | Should -Be 'Configure MrxSmb10 driver'
        (& $row 'smb|smb_driver').ChildValueDisplayName | Should -Be 'Disable driver (recommended)'
        (& $row 'rpc|rpc_protocol').ChildDisplayName | Should -Be 'Protocol to use for outgoing RPC connections'
        # Lists: in, every value.
        (& $row 'dev|dev_list').ChildExpected | Should -Be '{class-a}|{class-b}'
        (& $row 'dev|dev_list').ChildOperator | Should -Be 'in'
        (& $row 'ur_network|').Expected | Should -Be '*S-1-5-32-544;*S-1-5-32-555'
        (& $row 'ur_network|').Operator | Should -Be 'in'
        (& $row 'ur_network|').SettingDisplayName | Should -Be 'Access From Network'

        # Fill in three Recommendations; the other rows are skipped and listed.
        (& $row 'device_vendor_msft_policy_config_abovelock_allowcortanaabovelock|').Recommendation = '1.1'
        (& $row 'ur_network|').Recommendation = '90.2'
        (& $row 'dev|dev_list').Recommendation = '4.10.9.1.3'
        $rows | Export-Csv $csv -NoTypeInformation
        $out = @(New-JLMaesterTest -RepoPath $repo -Path $csv -Pack cis-win11-intune-l1 -Severity High -WarningVariable warned -WarningAction SilentlyContinue)
        $out.Title | Should -Be 'Allow Cortana Above Lock is set to Block',
        'Prevent installation of devices using drivers that match these device setup classes: Prevented Classes is set to Enabled: {class-a}, {class-b}',
        'Access From Network is set to *S-1-5-32-544, *S-1-5-32-555'
        "$warned" | Should -Match 'Skipped 6 row\(s\) without a Recommendation: row 3 \(Configure SMB v1 client driver\);'
        { Test-JLMaesterPack -RepoPath $repo -InformationAction SilentlyContinue } | Should -Not -Throw

        # With -Pack, the settings the pack tests are left out (dev has one child, which its test names).
        $null = Export-JLMaesterTestCsv -PolicyName 'W11_D_CISL1_*' -Path $csv -RepoPath $repo -Pack cis-win11-intune-l1
        @(Import-Csv $csv | ForEach-Object { & $key $_ }) | Should -Be 'smb|', 'smb|smb_driver', 'rpc|', 'rpc|rpc_protocol', 'rpc|rpc_auth'

        Set-Content $csv ('Recommendation,SettingDefinitionId', ',a')
        { New-JLMaesterTest -RepoPath $repo -Path $csv -Pack cis-win11-intune-l1 -Severity High -WarningAction SilentlyContinue } | Should -Throw '*has no row with a Recommendation*'
    }

    It 'checks several settings in one test, from the policy or a CSV row, and the pack still passes every check' {
        $repo = New-FixtureRepo
        $null = New-FixturePack -Repo $repo
        $timers = 'mcx_desktop_display sleep timer', 'mcx_battery_display sleep timer'
        # One value for all of them: a match pattern for "10 or less, but not 0".
        $out = New-JLMaesterTest -RepoPath $repo -Pack cis-win11-intune-l1 -Recommendation 2.11.1.1 -Severity Medium -FromPolicy 'MAC_D_CISL1_*' -SettingDefinitionId $timers -Operator match -Expected '^([1-9]|10)$' -ValueDisplayName '10 or less, but not 0'
        $out.Title | Should -Be 'Display Sleep Timer is set to 10 or less, but not 0'
        $out.Area | Should -Be 'Energy Saver'
        $out.FunctionName | Should -Be 'Test-JLMcxDisplaySleepTimer'
        $out.SettingDefinitionId | Should -Be $timers
        $ps1 = Read-Text (Join-Path $repo 'cis-win11-intune-l1/tests/Test.MP.JL.CISW11INT.L1.001.ps1')
        $ps1 | Should -Match ([regex]::Escape("[string[]] `$SettingDefinitionId = ('mcx_desktop_display sleep timer', 'mcx_battery_display sleep timer'),"))
        $ps1 | Should -Match ([regex]::Escape("[string[]] `$Expected = '^([1-9]|10)$',"))
        $ps1 | Should -Match "Operator\s+= 'match'"
        $out.Markdown | Should -Match ([regex]::Escape('set each of **Energy Saver > Desktop Power > Display Sleep Timer** and **Energy Saver > Laptop Battery Power > Display Sleep Timer** to **10 or less, but not 0**'))
        $out.Markdown | Should -Match ([regex]::Escape('2. Add **Energy Saver** > **Desktop Power** > **Display Sleep Timer** and **Energy Saver** > **Laptop Battery Power** > **Display Sleep Timer** and set each to'))
        $out.Markdown | Should -Match 'policies for macOS set each of'

        # A choice setting: the label picks each setting's own option id, from a CSV row (ids separated by ';').
        $csv = Join-Path $repo 'mac.csv'
        Set-Content $csv ('Recommendation,Severity,FromPolicy,SettingDefinitionId,ValueDisplayName', '2.11.1.3,Medium,MAC_D_CISL1_*,mcx_desktop_wake on lan;mcx_battery_wake on lan,False')
        $wake = @(New-JLMaesterTest -RepoPath $repo -Path $csv -Pack cis-win11-intune-l1)
        $wake.Title | Should -Be 'Wake on LAN is set to False'
        $ps1 = Read-Text (Join-Path $repo 'cis-win11-intune-l1/tests/Test.MP.JL.CISW11INT.L1.002.ps1')
        $ps1 | Should -Match ([regex]::Escape("[string[]] `$Expected = ('mcx_desktop_wake on lan_0', 'mcx_battery_wake on lan_0'),"))
        { Test-JLMaesterPack -RepoPath $repo -InformationAction SilentlyContinue } | Should -Not -Throw

        # Export -Pack leaves out the settings the tests check.
        $export = Join-Path $repo 'export.csv'
        $null = Export-JLMaesterTestCsv -PolicyName 'MAC_D_CISL1_*' -Path $export -RepoPath $repo -Pack cis-win11-intune-l1
        @(Import-Csv $export) | Should -BeNullOrEmpty

        { New-JLMaesterTest -RepoPath $repo -Pack cis-win11-intune-l1 -Recommendation 9.9 -Severity Medium -SettingDefinitionId $timers -Expected 1 -SettingDisplayName T -ValueDisplayName 1 -CategoryPath C -WhatIf } | Should -Throw '*need -FromPolicy*'
        { New-JLMaesterTest -RepoPath $repo -Pack cis-win11-intune-l1 -Recommendation 9.9 -Severity Medium -FromPolicy 'MAC_D_CISL1_*' -SettingDefinitionId $timers -Expected 1, 2, 3 -ValueDisplayName 1 -WhatIf } | Should -Throw '*one value for all of them, or one per setting*'
        { New-JLMaesterTest -RepoPath $repo -Pack cis-win11-intune-l1 -Recommendation 9.9 -Severity Medium -FromPolicy 'MAC_D_CISL1_*' -SettingDefinitionId $timers -ChildSettingDefinitionId x -WhatIf } | Should -Throw '*one -SettingDefinitionId*'
        { New-JLMaesterTest -RepoPath $repo -Pack cis-win11-intune-l1 -Recommendation 9.9 -Severity Medium -FromPolicy 'MAC_D_CISL1_*' -SettingDefinitionId 'mcx_desktop_display sleep timer', nope -WhatIf } | Should -Throw "*sets 'nope'*"
    }

    It 'picks another option by its label' {
        $repo = New-FixtureRepo
        $null = New-FixturePack -Repo $repo
        $out = New-JLMaesterTest -RepoPath $repo -Pack cis-win11-intune-l1 -Recommendation 1.1 -Severity High -FromPolicy 'W11_D_CISL1_*' -SettingDisplayName 'Allow Cortana Above Lock' -ValueDisplayName Allow -Description 'x' -Product Intune -Feature F -Area A -WhatIf
        $out.Expected | Should -Be 'device_vendor_msft_policy_config_abovelock_allowcortanaabovelock_1'
        { New-JLMaesterTest -RepoPath $repo -Pack cis-win11-intune-l1 -Recommendation 1.1 -Severity High -FromPolicy 'W11_D_CISL1_*' -SettingDisplayName 'Allow Cortana Above Lock' -ValueDisplayName Maybe -Description 'x' -Product Intune -Feature F -Area A -WhatIf } | Should -Throw '*no option labelled*Block*Allow*'
    }
}

Describe 'Sync-JLMaesterHelper' {
    It 'refuses a helper file that does not hold exactly one function named after it' {
        $repo = New-FixtureRepo
        $null = New-FixturePack -Repo $repo
        Set-Content (Join-Path $repo 'shared/helpers/Get-JlTwo.ps1') "function Get-JlTwo {}`nfunction Get-JlOther {}"
        { Sync-JLMaesterHelper -RepoPath $repo -Check -InformationAction SilentlyContinue } | Should -Throw '*exactly one function*'
    }

    It 'reports a pack whose helpers are out of date, and fixes it' {
        $repo = New-FixtureRepo
        $null = New-FixturePack -Repo $repo
        Add-Content (Join-Path $repo 'shared/helpers/Test-JlIntuneSetting.ps1') '# changed'
        { Sync-JLMaesterHelper -RepoPath $repo -Check -InformationAction SilentlyContinue } | Should -Throw '*out of sync*'
        Sync-JLMaesterHelper -RepoPath $repo -InformationAction SilentlyContinue
        { Sync-JLMaesterHelper -RepoPath $repo -Check -InformationAction SilentlyContinue } | Should -Not -Throw
    }
}
