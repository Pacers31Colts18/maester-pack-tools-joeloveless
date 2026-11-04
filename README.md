# Maester Pack Tools

`JLMaesterTools`, a PowerShell module for writing the [Maester Packs](https://maester.dev/docs/packs) in
[maester-packs-joeloveless](https://github.com/Pacers31Colts18/maester-packs-joeloveless): create a pack, add a test per
setting, look up setting ids in your tenant, sync the shared helpers and run the pack checks. It writes files only;
the packs repository holds the packs and their shared helpers.

Needs PowerShell 7.4 or later and Maester 3.0 or later (`Install-PSResource Maester -Prerelease` until 3.0 is released).

## Install

```powershell
git clone https://github.com/Pacers31Colts18/maester-pack-tools-joeloveless C:\Users\jlove\GitHub\maester-pack-tools-joeloveless
Import-Module C:\Users\jlove\GitHub\maester-pack-tools-joeloveless\JLMaesterTools\JLMaesterTools.psd1
```

The packs repository's `tools/*.ps1` scripts find the module on their own when this repository is cloned next to it.

## Functions

| Function | What it does |
| --- | --- |
| `New-JLMaesterPack` | A new pack for one baseline profile: manifest, guide, README, suite, framework file with the benchmark name and version, helpers, the repository README row and a CHANGELOG section. Undoes everything if the pack fails the checks |
| `New-JLMaesterTest` | A setting test, numbered after the pack's last one (Area comes from the setting's Intune category, Product and Feature from the pack's framework file): `Test.<ID>.ps1` and `.md` from the template, the framework requirement, the README row, the CHANGELOG line and a version bump once the current version is released. `-FromPolicy` reads the ids from a policy in your tenant, with the child settings it configures under the setting (checked in the same policy; `-NoChildren` skips them); `-WhatIf` returns both drafts without writing. `-Path tests.csv` writes one test per row, all or nothing |
| `Find-JLIntuneSetting` | Read-only lookup in your tenant's settings catalog policies: setting definition id, configured value, every option with its label, category |
| `Sync-JLMaesterHelper` | Copies `shared/helpers` into every pack (`-Check` only compares) |
| `Test-JLMaesterPack` | The checks CI runs: helpers in sync, `Test-MtPack` valid with Low risk and no findings, every test valid, the benchmark version named consistently, every test runnable |

Every function takes `-RepoPath` (default: the current folder). `Get-Help <function> -Full` has the details.

## Examples

```powershell
cd C:\Users\jlove\GitHub\maester-packs-joeloveless

# Find a setting's ids in a policy that already has it (needs Connect-Maester)
Find-JLIntuneSetting -PolicyName 'W11_D_CISL1_*' -Name 'Allow Cortana*' | Format-List

# Draft a test from that policy, review it, then write it. Area is the setting's own Intune category, such as
# Personalization (the .md names the whole path; pass -Area to override it); Product and Feature come from
# the pack's framework file.
$draft = New-JLMaesterTest -Pack cis-win11-intune-l1 -Recommendation 1.1 -Severity High `
    -FromPolicy 'W11_D_CISL1_*' -SettingDisplayName 'Allow Cortana Above Lock' -ValueDisplayName Block `
    -Description 'Cortana should not answer voice requests while the device is locked.' -WhatIf
$draft.Ps1; $draft.Markdown
New-JLMaesterTest -Pack cis-win11-intune-l1 -Recommendation 1.1 -Severity High `
    -FromPolicy 'W11_D_CISL1_*' -SettingDisplayName 'Allow Cortana Above Lock' -ValueDisplayName Block `
    -Description 'Cortana should not answer voice requests while the device is locked.'

# Many tests from a CSV: write it from your policies, fill in the Recommendation column (rows left empty are
# skipped), draft them all, then write them all (or none, if any row fails)
Export-JLMaesterTestCsv -PolicyName 'W11_D_CISL1_*' -Pack cis-win11-intune-l1 -Path .\tests.csv
New-JLMaesterTest -Path .\tests.csv -Pack cis-win11-intune-l1 -WhatIf | Format-Table Row, Id, Title, Area, Children
New-JLMaesterTest -Path .\tests.csv -Pack cis-win11-intune-l1

# A new pack for another profile
New-JLMaesterPack -Folder cis-win11-intune-l2 -Code JL.CISW11INT.L2 -Name 'CIS Windows 11 Intune L2' `
    -FrameworkKey cis-intune-win11-l2 -BenchmarkName 'CIS Microsoft Intune for Windows 11 Benchmark' `
    -BenchmarkVersion 5.0.0 -BenchmarkUrl https://www.cisecurity.org/benchmark/intune -Level L2 -Tags CIS-Intune, L2

Test-JLMaesterPack
```

Test IDs are numbers: `MP.<Code>.001`, `MP.<Code>.002`, ... in the order tests are added (the pack's next free number;
a CSV run numbers its rows in order). `-Recommendation` stays with the test: it is the test's `Control`, which links it
to the framework requirement, and the `.md` opens with a `#### Description` section that names it:

```markdown
#### Description

<your -Description, when given>

CIS Microsoft Intune for Windows 11 Benchmark, recommendation 4.4.2 (Level 1).

The test passes when ...
```

Write each test's `-Description` in your own words. Benchmark text is usually licensed; the test names the
recommendation number instead.

`Export-JLMaesterTestCsv -PolicyName '<policies>' -Path <csv>` writes the CSV for you from the policies: one row for each setting, and for a setting with children one row for the setting alone (`NoChildren` true) and one per child (picked with `ChildSettingDefinitionId`), as CIS numbers them for BitLocker. When the benchmark numbers a setting and its children as one recommendation (such as SMB v1), delete the child rows and clear `NoChildren`. A list (a user right, a deny list) gets every value with `in`; change it to `contains` when the benchmark says the list must include them. Names and value labels come from the policy. With `-Pack`, settings the pack already tests are left out. Fill in `Recommendation`; `New-JLMaesterTest -Path` skips and lists the rows you leave empty.

A CSV for `-Path` has one test per row and `New-JLMaesterTest` parameter names as columns; an unknown column stops
the run. Empty cells are left out, and `SettingDefinitionId`, `Expected` and the `Child*` columns take several values
separated by `;`.
Parameters passed with `-Path` apply to every row, and a cell overrides them. Every row needs `Recommendation`,
`Pack` and `Severity` (in a cell or passed with `-Path`) and the setting. With `FromPolicy`, the setting definition
id is enough: the name, value, category and children come from the policy. `Find-JLIntuneSetting -PolicyName
'<policies>' | Export-Csv` lists every id. `Area` is optional, as in a single run:

```csv
Recommendation,FromPolicy,SettingDefinitionId,ChildSettingDefinitionId
4.4.1,W11_D_CISL1_*,device_vendor_msft_policy_config_mssecurityguide_applyuacrestrictionstolocalaccountsonnetworklogon,
4.7.3,W11_D_CISL1_*,device_vendor_msft_policy_config_printers_configurerpcconnectionpolicy,device_vendor_msft_policy_config_printers_configurerpcconnectionpolicy_rpcconnectionprotocol_enum
```

Every child the policy configures under the setting is checked. When the benchmark numbers a parent's children
separately (CIS writes them `<setting>: <child>`), `ChildSettingDefinitionId` picks the one the row checks, as 4.7.3
above; its title is `<setting>: <child> is set to Enabled: <child value>`. Each test's function is named after the
setting definition id (or the picked child's), without the shared `device_vendor_msft_policy_config_` prefix:
`abovelock_allowtoasts` gives `Test-JLAbovelockAllowtoasts`, so settings with the same name (such as the four event
logs) never collide. A setting with several values, such as a user right's accounts, is
checked with `in` unless the row sets `Operator`: every account the policy grants must be one of them.

When one recommendation needs the same setting in several places, such as macOS Energy Saver's Display Sleep Timer
under Desktop Power, Laptop Battery Power and Laptop Power, put every id in `SettingDefinitionId` (`a;b;c`, with
`FromPolicy`): one test, which passes only when each setting passes on its own. `Expected` is one value for all of
them (a `match` pattern such as `^([1-9]|10)$`) or one per setting in the same order (a choice setting's option ids
differ per setting; `ValueDisplayName` alone also picks each one's option by its label). Area is the category the
settings share (Energy Saver), and the function is named after the parts of the ids they share. Such a test takes no
child settings.

Area has no default for compliance and configuration profile settings (no Intune category); pass `-Area` for those.

`-Operator` sets how the value is compared, and the title says it in words: `ne` "is not set to", `contains` "includes"
(a user right that must include Guests), `ge` / `le` "is at least" / "is at most", `in` "is set to" one of several
(`Expected` `a;b`, `ValueDisplayName` such as `Success or Success and Failure`). Children are compared with `eq` unless
`-ChildOperator` says otherwise, one per child: `ge` for a size "or greater", `in` with the values separated by `|` in
`ChildExpected` (a CSV cell already uses `;` between children), `exists` for any value (no `ChildExpected`; the
policy's value stays out of the test). With `-FromPolicy`, `-ChildExpected`, `-ChildDisplayName` and
`-ChildValueDisplayName` replace the policy's values and names for picked children, such as `32768` and `32,768 or more`;
the policy must still configure each picked child.

`-Replace` rewrites the test that already checks `-Recommendation`, under the same ID: its files, README row and
CHANGELOG line, keeping its Severity and Description unless passed (a CSV takes a `Replace` column of `true`).

A recommendation no Intune policy setting can show, such as a service a script disables, gets an always-skipped test:
`-SkipReason '<why>'` with `-SettingDisplayName`, `-ValueDisplayName` and `-Area`, and no setting. It keeps its number,
Control and title, so the report lists it as skipped with that reason; a CSV takes the same as a `SkipReason` column.

## Develop

```powershell
Invoke-Pester ./tests
```

The tests build a packs repository in Pester's TestDrive, run the real Maester checks on what the module writes, and
mock Microsoft Graph.

## License

[MIT](LICENSE)
