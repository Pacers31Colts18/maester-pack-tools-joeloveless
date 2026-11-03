function Resolve-JLPack {
    <#
    .SYNOPSIS
        One pack of a packs repository: its folder, manifest, suite and framework file (exactly one framework per pack).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Repo,
        [Parameter(Mandatory)] [string] $Pack
    )

    $path = Join-Path $Repo $Pack
    $manifestPath = Join-Path $path 'maester-pack.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        $known = @(Get-JLPackFolder -Repo $Repo | ForEach-Object { $_.Name }) -join ', '
        throw "There is no pack folder '$Pack' in $Repo. Packs: $(if ($known) { $known } else { 'none' })."
    }
    $suitePath = Join-Path $path 'tests/suite.json'
    $suite = Get-Content -LiteralPath $suitePath -Raw | ConvertFrom-Json
    $keys = @($suite.Frameworks | ForEach-Object { [string]$_.Key } | Where-Object { $_ })
    if ($keys.Count -ne 1) { throw "$Pack/tests/suite.json must declare exactly one framework; it declares $($keys.Count)." }
    $frameworkPath = Join-Path $path "tests/frameworks/$($keys[0]).json"
    if (-not (Test-Path -LiteralPath $frameworkPath)) { throw "$Pack/tests/frameworks/$($keys[0]).json is missing." }

    [pscustomobject]@{
        Folder        = $Pack
        Path          = $path
        ManifestPath  = $manifestPath
        Manifest      = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        SuitePath     = $suitePath
        Suite         = $suite
        FrameworkKey  = $keys[0]
        FrameworkPath = $frameworkPath
        Framework     = Get-Content -LiteralPath $frameworkPath -Raw | ConvertFrom-Json
        ReadmePath    = Join-Path $path 'README.md'
    }
}
