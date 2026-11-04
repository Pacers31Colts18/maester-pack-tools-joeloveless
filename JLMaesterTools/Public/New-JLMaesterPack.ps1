function New-JLMaesterPack {
    <#
    .SYNOPSIS
        Creates a pack in a packs repository: one baseline profile, ready for New-JLMaesterTest.

    .DESCRIPTION
        Runs New-MtPack for the Guid and Maester's own checks of the Id and Code, then writes the repository's layout:
        maester-pack.json (read-only Graph scopes, Banner assets/banner.png), maester-pack.guide.json, README.md,
        tests/suite.json and the framework file that holds the benchmark name and version. It creates the assets
        folder but not the banner: add assets/banner.png (PNG, at most 1 MB) before the first release. Copies the shared helpers in, adds the pack's row to
        the repository README and a '## <folder> 0.1.0' section to CHANGELOG.md, then runs Test-JLMaesterPack on it.
        If anything fails, the pack folder is removed and the README and CHANGELOG are put back.

        The Code and Guid can never change once the pack is released: a new Code is a new pack.

    .PARAMETER Folder
        The pack's folder, which is also the second part of its Id: pacers31colts18.<folder>.

    .PARAMETER Code
        The start of every test ID: MP.<Code>.<recommendation>. Up to three dot-separated parts of 2-10 letters or
        digits, each starting with a letter, such as JL.CISW11INT.L2.

    .PARAMETER Name
        The display name, such as 'CIS Windows 11 Intune L2'.

    .PARAMETER FrameworkKey
        The framework key that tests name in Control, such as cis-intune-win11-l2. One per pack.

    .PARAMETER BenchmarkName
        The benchmark's name, such as 'CIS Microsoft Intune for Windows 11 Benchmark'.

    .PARAMETER BenchmarkVersion
        The benchmark's version, such as 5.0.0. Set once, in the framework file.

    .PARAMETER BenchmarkUrl
        Where the benchmark is published.

    .PARAMETER Level
        The profile, such as L2: written to the framework file as the default Level of new tests, and used in the
        descriptions ('Level 2 recommendations').

    .PARAMETER Product
        The product every test of the pack is grouped under in the Maester report (its Category), written to the
        framework file for New-JLMaesterTest. Default: Intune.

    .PARAMETER Tags
        Suite tags that select every test of the pack, such as 'CIS-Intune', 'L2'. Maester reserves CIS, MT, Maester,
        Custom, All and the other built-in suite names.

    .PARAMETER Description
        The manifest Description. Defaults to one built from the benchmark; it must name v<BenchmarkVersion>.

    .EXAMPLE
        New-JLMaesterPack -Folder cis-win11-intune-l2 -Code JL.CISW11INT.L2 -Name 'CIS Windows 11 Intune L2' `
            -FrameworkKey cis-intune-win11-l2 -BenchmarkName 'CIS Microsoft Intune for Windows 11 Benchmark' `
            -BenchmarkVersion 5.0.0 -BenchmarkUrl https://www.cisecurity.org/benchmark/intune -Level L2 -Tags CIS-Intune, L2
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [ValidatePattern('^[a-z0-9]([a-z0-9-]{0,62}[a-z0-9])?$')] [string] $Folder,
        [Parameter(Mandatory)] [ValidatePattern('^[A-Za-z][A-Za-z0-9]{1,9}(\.[A-Za-z][A-Za-z0-9]{1,9}){0,2}$')] [string] $Code,
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [ValidatePattern('^[a-z0-9][a-z0-9.-]*$')] [string] $FrameworkKey,
        [Parameter(Mandatory)] [string] $BenchmarkName,
        [Parameter(Mandatory)] [ValidatePattern('^\d+(\.\d+){0,3}$')] [string] $BenchmarkVersion,
        [string] $BenchmarkUrl,
        [string] $Level,
        [ValidateLength(1, 40)] [string] $Product = 'Intune',
        [string[]] $Tags = @(),
        [string[]] $Categories = @('Intune', 'Devices', 'Windows'),
        [string] $Description,
        [string] $RepoPath = (Get-Location).Path,
        [string] $Publisher = 'pacers31colts18',
        [string] $GitHubRepository = 'Pacers31Colts18/maester-packs-joeloveless'
    )

    $ErrorActionPreference = 'Stop'
    Assert-JLMaester
    $repo = Resolve-JLPacksRepo -RepoPath $RepoPath
    $packPath = Join-Path $repo $Folder
    if (Test-Path -LiteralPath $packPath) { throw "$packPath already exists." }

    $reserved = 'Maester', 'MT', 'CIS', 'CISA', 'EIDSCA', 'ORCA', 'AD', 'ASD', 'AZDO', 'XSPM', 'All', 'Custom'
    foreach ($tag in $Tags) { if ($reserved -contains $tag) { throw "The tag '$tag' is reserved for the checks that ship with Maester. Use a name of your own, such as 'CIS-Intune'." } }
    foreach ($other in (Get-JLPackFolder -Repo $repo)) {
        $info = Resolve-JLPack -Repo $repo -Pack $other.Name
        $otherCode = [string]$info.Manifest.Code
        if ($otherCode -eq $Code -or $otherCode.StartsWith("$Code.", 'OrdinalIgnoreCase') -or $Code.StartsWith("$otherCode.", 'OrdinalIgnoreCase')) {
            throw "The Code $Code overlaps the Code $otherCode of $($other.Name); two installed packs may not share a code or have one that starts with the other."
        }
        if ($info.FrameworkKey -eq $FrameworkKey) { throw "The framework key $FrameworkKey is already declared by $($other.Name); each pack needs its own." }
    }

    $profileText = if ($Level -match '^L(\d+)$') { "Level $($Matches[1])" } elseif ($Level) { $Level } else { '' }
    $recommendations = if ($profileText) { "$profileText recommendations" } else { 'recommendations' }
    if (-not $Description) { $Description = "Checks that Intune policies configure the $recommendations of the $BenchmarkName v$BenchmarkVersion. One test per setting." }
    elseif ($Description -notmatch [regex]::Escape("v$BenchmarkVersion")) { throw "-Description must name the benchmark version as v$BenchmarkVersion; Test-JLMaesterPack checks that it does." }
    $summary = if ($PSBoundParameters.ContainsKey('Description')) { "$Description It reads policy configuration, not device state." }
    else { "Checks that your Intune policies configure the $recommendations of the $BenchmarkName v$BenchmarkVersion, one test per setting. It reads policy configuration, not device state." }
    $benchmarkLink = if ($BenchmarkUrl) { "[$BenchmarkName]($BenchmarkUrl)" } else { $BenchmarkName }
    $id = "$Publisher.$Folder"

    if (-not $PSCmdlet.ShouldProcess($packPath, "Create pack $id (Code $Code)")) { return }

    $readmePath = Join-Path $repo 'README.md'
    $changelogPath = Join-Path $repo 'CHANGELOG.md'
    $state = Save-JLFileState -Path $readmePath, $changelogPath
    try {
        New-MtPack -Path $packPath -Id $id -Code $Code -Name $Name | Out-Null
        $guid = [string](Get-Content -LiteralPath (Join-Path $packPath 'maester-pack.json') -Raw | ConvertFrom-Json).Guid
        Get-ChildItem -LiteralPath (Join-Path $packPath 'tests') -Filter 'Test.*' | Remove-Item

        $manifest = [ordered]@{
            '$schema'       = 'https://maester.dev/schemas/maester-pack-1.0.json'
            Id              = $id
            Guid            = $guid
            Name            = $Name
            Description     = $Description
            Version         = '0.1.0'
            Publisher       = $Publisher
            License         = 'MIT'
            Homepage        = "https://github.com/$GitHubRepository/tree/main/$Folder"
            Support         = "https://github.com/$GitHubRepository/issues"
            RequiresMaester = '>=3.0'
            Code            = $Code
            Suites          = @('tests')
            Helpers         = @('helpers')
            Guide           = 'maester-pack.guide.json'
            Banner          = 'assets/banner.png'
            Uses           = [ordered]@{
                Services     = @('Graph')
                GraphScopes  = @('DeviceManagementConfiguration.Read.All', 'GroupMember.Read.All')
                TenantWrites = @()
                Network      = @()
                Modules      = @()
            }
            Categories      = @($Categories)
        }
        Write-JLTextFile -Path (Join-Path $packPath 'maester-pack.json') -Text ($manifest | ConvertTo-Json -Depth 6)
        # The banner image is added by hand; until it is, git does not track the empty folder.
        New-Item -ItemType Directory -Path (Join-Path $packPath 'assets') -Force | Out-Null

        $guide = [ordered]@{
            '$schema'     = 'https://maester.dev/schemas/maester-pack-guide-1.0.json'
            Summary       = $summary
            Prerequisites = @(
                [ordered]@{ Text = 'PowerShell 7.4 or later and Maester 3.0 or later.' }
                [ordered]@{ Text = 'An account that can read Intune configuration, such as Global Reader or Intune Administrator.' }
            )
            Connect       = [ordered]@{ Steps = @([ordered]@{ Text = "Connect Maester. Its default Graph scopes include everything this pack reads."; Command = 'Connect-Maester' }) }
            Run           = [ordered]@{
                Commands = @(
                    [ordered]@{ Text = 'Only this pack'; Command = "Invoke-Maester -Pack $Code -SkipBuiltIn" }
                    [ordered]@{ Text = "Maester's tests and this pack"; Command = "Invoke-Maester -Pack $Code" }
                )
                Options  = @(
                    [ordered]@{ Name = 'JLIntune.PolicyNameFilter'; Default = '(none)'; Text = "GlobalSettings: a wildcard such as 'W11-CIS-*'. Only policies whose name matches count, in every test that does not set its own PolicyNameFilter." }
                    [ordered]@{ Name = '<test> PolicyNameFilter'; Default = '(none)'; Text = 'The same filter for one test, in TestSettings.' }
                    [ordered]@{ Name = '<test> IncludeUnassigned'; Default = 'false'; Text = 'Count policies that are not assigned to anything.' }
                    [ordered]@{ Name = '<test> AllowConflicts'; Default = 'false'; Text = 'Pass even when another counted policy sets a value that does not meet the recommendation.' }
                )
            }
            AppOnly       = [ordered]@{
                Supported = $true
                Methods   = [ordered]@{ Certificate = $true; ClientSecret = $true; ManagedIdentity = $true; WorkloadIdentity = $true }
                Text      = "Give the app the application permissions listed on this page, connect with Connect-MgGraph, and run Invoke-Maester -Pack $Code -SkipBuiltIn -SkipGraphConnect -NonInteractive."
            }
            Support       = [ordered]@{ Pack = "https://github.com/$GitHubRepository/issues" }
        }
        Write-JLTextFile -Path (Join-Path $packPath 'maester-pack.guide.json') -Text ($guide | ConvertTo-Json -Depth 6)

        $suite = [ordered]@{
            Id              = $Code
            Name            = $Name
            Source          = 'Custom'
            Tags            = @($Tags)
            RequiresMaester = '3.0'
            Frameworks      = @([ordered]@{ Key = $FrameworkKey })
        }
        Write-JLTextFile -Path (Join-Path $packPath 'tests/suite.json') -Text ($suite | ConvertTo-Json -Depth 4)

        $framework = [ordered]@{ Framework = $FrameworkKey; Name = $(if ($profileText) { "$BenchmarkName ($profileText)" } else { $BenchmarkName }); Version = $BenchmarkVersion }
        if ($BenchmarkUrl) { $framework.Url = $BenchmarkUrl }
        if ($Level) { $framework.Level = $Level }
        $framework.Product = $Product
        $framework.Notes = 'The one place this pack''s benchmark name and version are set. Maester writes Version on every result row. Test-JLMaesterPack fails until the manifest Description, the guide Summary and both READMEs say v<Version>. New-JLMaesterTest gives every test Product from here and Feature from Name without (Level n), followed by the pack''s level, such as (L1); Maester ignores Product.'
        $framework.Requirements = @()
        Write-JLFrameworkFile -Path (Join-Path $packPath "tests/frameworks/$FrameworkKey.json") -Framework ([pscustomobject]$framework)

        $readme = @"
# $Name

A [Maester Pack](https://maester.dev/docs/packs) that checks your Intune policies against the $recommendations of
the $benchmarkLink v$BenchmarkVersion. One test per setting; tests are numbered in the order they were added (MP.$Code.001), and each test's description names
its recommendation.

The tests read policy configuration (a policy exists, is assigned and has the value), not whether devices applied it.

## Install and run

    Install-MtPack $GitHubRepository/$Folder
    Connect-Maester
    Invoke-Maester -Pack $Code

Maester's default Graph scopes include what the pack reads (``DeviceManagementConfiguration.Read.All``, and
``GroupMember.Read.All`` to show group names). An account with the Global Reader role is enough.

## How a setting test decides

A test passes when at least one **assigned** policy sets the setting as the recommendation requires and no other
assigned policy sets it to something else. What a test checks is in its parameters, with the recommendation's values
as defaults (``Get-MtTest -Path ./$Folder | Select-Object -ExpandProperty Parameters`` lists them):

| Parameter | Default | Effect |
| --- | --- | --- |
| ``Source`` | per test | ``settingsCatalog``, ``compliance`` or ``deviceConfiguration``. |
| ``Platform`` | per test | settingsCatalog: the platform the policy targets, such as ``windows10``. |
| ``SettingDefinitionId`` | per test | settingsCatalog: the setting checked. (``Property`` and ``ODataType`` for the other sources.) |
| ``Expected`` | per test | The value the recommendation requires. |
| ``PolicyNameFilter`` | none | Only policies whose name matches this wildcard count. |
| ``IncludeUnassigned`` | ``false`` | Count policies that are not assigned to anything. |
| ``AllowConflicts`` | ``false`` | Pass even when a counted policy sets a conflicting value. |

Changing ``Source``, ``Platform``, ``SettingDefinitionId`` or ``Expected`` in the config changes what the test checks; the
result row records that the value came from ``Config``. Set a filter for every test at once with ``GlobalSettings``, or
tune one test with ``TestSettings``, in ``maester-config.json``:

``````json
{
  "GlobalSettings": { "JLIntune.PolicyNameFilter": "W11-CIS-*" }
}
``````

## Moving to a new benchmark version

The benchmark's name and version are set in one place: ``tests/frameworks/$FrameworkKey.json`` (``Name``,
``Version``). Maester writes that version on every result row.

1. Change ``Version`` in the framework file.
2. Run ``Test-JLMaesterPack``. It fails and lists each text that still names the old version (the manifest
   ``Description``, the guide ``Summary``, this README and the repository README). Update them.
3. Update the tests whose recommendations changed, and the ``Requirements`` in the framework file: add new
   recommendation IDs, remove withdrawn ones.
4. Bump ``Version`` in ``maester-pack.json`` and add a ``## $Folder <version>`` entry to ``CHANGELOG.md``.

The pack's Code and test IDs stay the same, so ``Update-MtPack`` moves everyone to the new release.

## Tests

| ID | Recommendation # | Title | Severity |
| --- | --- | --- | --- |
"@
        Write-JLTextFile -Path (Join-Path $packPath 'README.md') -Text $readme

        Sync-JLMaesterHelper -RepoPath $repo -InformationAction SilentlyContinue
        $checks = if ($profileText) { "$BenchmarkName v$BenchmarkVersion, $profileText" } else { "$BenchmarkName v$BenchmarkVersion" }
        Add-JLMarkdownTableRow -Path $readmePath -Header '| Pack | Folder | Code | Checks |' -Row "| $Name | [$Folder]($Folder/README.md) | ``$Code`` | $checks |"
        Add-JLChangelogLine -Path $changelogPath -Folder $Folder -Version '0.1.0' -Intro 'First version.'
        Test-JLMaesterPack -RepoPath $repo -Pack $Folder -InformationAction SilentlyContinue
    } catch {
        if (Test-Path -LiteralPath $packPath) { Remove-Item -LiteralPath $packPath -Recurse -Force }
        Restore-JLFileState -State $state
        throw
    }

    [pscustomobject]@{ Folder = $Folder; Id = $id; Code = $Code; Guid = $guid; Path = $packPath; FrameworkKey = $FrameworkKey }
}
