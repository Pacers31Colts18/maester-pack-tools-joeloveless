function Assert-JLMaester {
    <#
    .SYNOPSIS
        Makes sure Maester 3.0 or later is loaded, for Test-MtPack, Get-MtTest, Invoke-MtTest and New-MtPack.
    #>
    [CmdletBinding()]
    param()

    if (Get-Module Maester | Where-Object Version -GE '3.0.0') { return }
    if (-not (Get-Module -ListAvailable Maester | Where-Object Version -GE '3.0.0')) {
        throw 'Maester 3.0 or later is required in PowerShell 7: Install-PSResource Maester -Prerelease.'
    }
    Import-Module Maester -MinimumVersion 3.0.0 -Global -ErrorAction Stop
}
