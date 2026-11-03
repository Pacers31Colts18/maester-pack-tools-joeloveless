function Find-JLIntuneSetting {
    <#
    .SYNOPSIS
        Looks up settings in the settings catalog policies of the connected tenant: their setting definition id, the
        value each policy sets, and every option with its label. Read-only.

    .DESCRIPTION
        Reads the policies whose name matches -PolicyName, with their settings and setting definitions, and returns one
        object per configured setting (child settings included) that matches -Name and -SettingDefinitionId. Use the
        result, or New-JLMaesterTest -FromPolicy, to fill a test's SettingDefinitionId and Expected value without
        copying ids by hand. Needs a Microsoft Graph connection (Connect-Maester or Connect-MgGraph) with
        DeviceManagementConfiguration.Read.All.

    .PARAMETER PolicyName
        The policy name, or a wildcard such as 'W11_D_CISL1_*'.

    .PARAMETER Name
        The setting's display name as Intune shows it, or a wildcard, such as 'Allow Cortana Above Lock'.

    .PARAMETER SettingDefinitionId
        The setting definition id, or a wildcard, such as '*abovelock*'.

    .EXAMPLE
        Find-JLIntuneSetting -PolicyName 'W11_D_CISL1_*' -Name 'Allow Cortana*'

    .EXAMPLE
        Find-JLIntuneSetting -PolicyName 'W11 baseline' | Format-Table DisplayName, ValueDisplayName, SettingDefinitionId
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $PolicyName,
        [string] $Name = '*',
        [string] $SettingDefinitionId = '*'
    )

    $ErrorActionPreference = 'Stop'
    if (-not (Get-Command Get-MgContext -ErrorAction SilentlyContinue) -or -not (Get-MgContext)) {
        throw 'Not connected to Microsoft Graph. Run Connect-Maester (or Connect-MgGraph -Scopes DeviceManagementConfiguration.Read.All) first.'
    }

    $policies = @(Invoke-JLGraphGet -Uri 'beta/deviceManagement/configurationPolicies?$select=id,name,platforms' | Where-Object { $_.name -like $PolicyName })
    if ($policies.Count -eq 0) { Write-Warning "No settings catalog policy is named like '$PolicyName'."; return }

    foreach ($policy in $policies) {
        $settings = @(Invoke-JLGraphGet -Uri "beta/deviceManagement/configurationPolicies('$($policy.id)')/settings?`$expand=settingDefinitions")
        foreach ($setting in $settings) {
            $definitions = @($setting.settingDefinitions)
            foreach ($flat in (ConvertTo-JLSettingValue -Instance $setting.settingInstance)) {
                $definition = $definitions | Where-Object { $_.id -eq $flat.Id } | Select-Object -First 1
                $displayName = if ($definition) { [string]$definition.displayName } else { '' }
                if ($flat.Id -notlike $SettingDefinitionId -or $displayName -notlike $Name) { continue }
                $options = @($definition.options | Where-Object { $null -ne $_ } | ForEach-Object { [pscustomobject]@{ ItemId = [string]$_.itemId; DisplayName = [string]$_.displayName } })
                $labels = @($flat.Values | ForEach-Object {
                        $value = [string]$_
                        $option = $options | Where-Object ItemId -EQ $value | Select-Object -First 1
                        if ($option) { $option.DisplayName } else { $value }
                    })
                [pscustomobject]@{
                    PolicyName                = [string]$policy.name
                    PolicyId                  = [string]$policy.id
                    Platform                  = [string]$policy.platforms
                    SettingDefinitionId       = $flat.Id
                    # The setting this one is nested under, such as the Administrative Templates setting whose Enabled
                    # holds it; empty at the top.
                    ParentSettingDefinitionId = $flat.ParentId
                    DisplayName               = $displayName
                    CategoryPath              = Get-JLCategoryPath -CategoryId ([string]$definition.categoryId)
                    Value                     = @($flat.Values | ForEach-Object { [string]$_ })
                    ValueDisplayName          = $labels -join ', '
                    Options                   = $options
                    InfoUrls                  = @($definition.infoUrls | Where-Object { $_ })
                }
            }
        }
    }
}
