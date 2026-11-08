function Test-JLMaesterPack {
    <#
    .SYNOPSIS
        The checks CI runs on a packs repository, for every pack folder or the ones named.
    .DESCRIPTION
        Helpers in sync with shared/helpers; Test-MtPack valid with Low risk and no findings; every test valid with
        Get-MtTest; the benchmark version of the framework file named in the manifest Description, the guide Summary,
        the pack README and the pack's row in the repository README; and every test run through the engine without an
        invalid or error row. Without a Graph connection the engine skips the tests (ServiceNotConnected), which still
        proves the metadata and parameters are valid. Throws when any check fails.
    .PARAMETER RepoPath
        The packs repository. Defaults to the current folder.
    .PARAMETER Pack
        Pack folders to check. Defaults to every pack.
    .EXAMPLE
        Test-JLMaesterPack
    .EXAMPLE
        Test-JLMaesterPack -RepoPath C:\Users\jlove\GitHub\maester-packs-joeloveless -Pack cis-win11-intune-l1
    #>
    [CmdletBinding()]
    param(
        [string] $RepoPath = (Get-Location).Path,
        [string[]] $Pack
    )

    $ErrorActionPreference = 'Stop'
    # Progress goes to the information stream, shown unless the caller passes -InformationAction.
    if (-not $PSBoundParameters.ContainsKey('InformationAction')) { $InformationPreference = 'Continue' }
    Assert-JLMaester
    $repo = Resolve-JLPacksRepo -RepoPath $RepoPath
    Sync-JLMaesterHelper -RepoPath $repo -Check -InformationAction $InformationPreference

    $folders = @(Get-JLPackFolder -Repo $repo)
    if ($Pack) { $folders = @($folders | Where-Object Name -In $Pack) }
    if ($folders.Count -eq 0) { throw 'No pack folders found.' }
    $repoReadme = Get-Content -LiteralPath (Join-Path $repo 'README.md')

    $failed = [System.Collections.Generic.List[string]]::new()
    foreach ($folder in $folders) {
        Write-Information "`n=== $($folder.Name)"

        $check = Test-MtPack $folder.FullName
        $check | Format-List Id, Version, IsValid, Risk, Errors, Warnings, Findings | Out-String -Width 200 | Write-Information
        if (-not $check.IsValid) { $failed.Add("$($folder.Name): Test-MtPack says the pack is not valid") }
        if ($check.Risk -ne 'Low') { $failed.Add("$($folder.Name): risk is $($check.Risk), must be Low") }
        if (@($check.Findings).Count -gt 0) { $failed.Add("$($folder.Name): $(@($check.Findings).Count) scan finding(s)") }

        $tests = @(Get-MtTest -Path $folder.FullName)
        foreach ($bad in @($tests | Where-Object { -not $_.IsValid })) { $failed.Add("$($folder.Name): $($bad.Id) is invalid: $(@($bad.Errors | ForEach-Object { if ($_.Message) { $_.Message } else { "$_" } }) -join '; ')") }
        $files = @(Get-ChildItem -LiteralPath (Join-Path $folder.FullName 'tests') -Filter 'Test.*.ps1')
        if ($tests.Count -ne $files.Count) { $failed.Add("$($folder.Name): $($files.Count) test file(s) but Get-MtTest found $($tests.Count)") }

        # The framework file is the one place the benchmark version is set; the human-facing text must say the same.
        $info = Resolve-JLPack -Repo $repo -Pack $folder.Name
        $version = [string]$info.Framework.Version
        if (-not $version) { $failed.Add("$($folder.Name): tests/frameworks/$($info.FrameworkKey).json has no Version") }
        else {
            $mentions = [ordered]@{
                "$($folder.Name)/maester-pack.json Description"   = [string]$info.Manifest.Description
                "$($folder.Name)/maester-pack.guide.json Summary" = [string](Get-Content -LiteralPath (Join-Path $folder.FullName 'maester-pack.guide.json') -Raw | ConvertFrom-Json).Summary
                "$($folder.Name)/README.md"                       = Get-Content -LiteralPath $info.ReadmePath -Raw
                "README.md (row for $($folder.Name))"             = [string]($repoReadme | Where-Object { $_ -like "*]($($folder.Name)/README.md)*" })
            }
            foreach ($where in $mentions.Keys) {
                if ($mentions[$where] -notmatch [regex]::Escape("v$version")) { $failed.Add("$($folder.Name): $where does not say v$version (the Version in tests/frameworks/$($info.FrameworkKey).json)") }
            }
        }

        if ($files.Count -eq 0) {
            Write-Information '(no tests yet; engine run skipped)'
            continue
        }
        $rows = @(Invoke-MtTest -Path $folder.FullName)
        $rows | Format-Table Id, Result, ReasonCode -AutoSize | Out-String -Width 200 | Write-Information
        $broken = @($rows | Where-Object { $_.Result -eq 'Error' -or $_.ReasonCode -in 'InvalidMetadata', 'InvalidReturn', 'InvalidConfiguration', 'DuplicateId' })
        foreach ($row in $broken) { $failed.Add("$($folder.Name): $($row.Id) $($row.Result) $($row.ReasonCode) $($row.ReasonDetail)") }
    }

    if ($failed.Count -gt 0) { throw "Pack checks failed:`n - " + ($failed -join "`n - ") }
    Write-Information "`nAll checks passed for $($folders.Count) pack(s)."
}
