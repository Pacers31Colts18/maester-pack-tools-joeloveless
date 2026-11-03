@{
    RootModule           = 'JLMaesterTools.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = '0fb3caac-0535-4394-8bf9-1fe2a593acb8'
    Author               = 'Joe Loveless'
    Copyright            = '(c) 2026 Joe Loveless. MIT License.'
    Description          = 'Authoring tools for Maester Packs that check Intune policy configuration: create packs and tests, look up setting ids in a tenant, sync shared helpers and run the pack checks.'
    PowerShellVersion    = '7.4'
    CompatiblePSEditions = @('Core')
    FunctionsToExport    = @(
        'Find-JLIntuneSetting'
        'New-JLMaesterPack'
        'New-JLMaesterTest'
        'Sync-JLMaesterHelper'
        'Test-JLMaesterPack'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{
        PSData = @{
            Tags       = @('Maester', 'Intune', 'MaesterPack', 'CIS')
            LicenseUri = 'https://github.com/Pacers31Colts18/maester-pack-tools-joeloveless/blob/main/LICENSE'
            ProjectUri = 'https://github.com/Pacers31Colts18/maester-pack-tools-joeloveless'
        }
    }
}
