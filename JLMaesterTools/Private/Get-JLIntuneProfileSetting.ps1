function Get-JLIntuneProfileSetting {
    <#
    .SYNOPSIS
        What the device configuration profiles (Device Restrictions, Device Features, ...) and compliance policies named
        like -PolicyName configure: one object per property, dots for nested, with its value. Read-only.

    .DESCRIPTION
        These policies have no setting definitions, so a property's Graph name is all there is: no display name, no
        option labels. Graph returns every property of a policy, configured or not; these count as not configured:
        null, false (the helper treats it so too), an empty text or list, and the values that mean the default
        (notConfigured, deviceDefault, ...). 0 is a value: Maximum minutes after screen lock set to Immediately is 0.

        A list of objects (such as home screen pages) has no property path to test, so it is left out with a warning.
        A compliance policy's actions for noncompliance are the exception: one object per kind of action, its grace
        period in hours, under a path that picks that kind.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $PolicyName)

    # On every policy; they say nothing about what it configures.
    $metadata = 'id', 'displayName', 'description', 'version', 'createdDateTime', 'lastModifiedDateTime', 'roleScopeTagIds', 'supportsScopeTags',
    'deviceManagementApplicabilityRuleOsEdition', 'deviceManagementApplicabilityRuleOsVersion', 'deviceManagementApplicabilityRuleDeviceMode', 'scheduledActionsForRule'
    $defaults = 'notConfigured', 'notSet', 'deviceDefault', 'browserDefault', 'none', 'allAllowed', 'unavailable'

    foreach ($source in @(
            @{ Name = 'deviceConfiguration'; Uri = 'beta/deviceManagement/deviceConfigurations' }
            @{ Name = 'compliance'; Uri = 'beta/deviceManagement/deviceCompliancePolicies?$expand=scheduledActionsForRule($expand=scheduledActionConfigurations)' }
        )) {
        foreach ($policy in @(Invoke-JLGraphGet -Uri $source.Uri | Where-Object { $_.displayName -like $PolicyName })) {
            $oDataType = [string]$policy.'@odata.type'
            $typeName = $oDataType -replace '^#?microsoft\.graph\.', ''
            # The names Intune gives these policies; a type it has no plain name for keeps the Graph name.
            $category = if ($source.Name -eq 'compliance') { 'Compliance' }
            elseif ($typeName -match 'General(Device)?Configuration$') { 'Device Restrictions' }
            elseif ($typeName -match 'DeviceFeaturesConfiguration$') { 'Device Features' }
            else { $typeName }
            $leftOut = [System.Collections.Generic.List[string]]::new()
            $setting = {
                param($Path, [string[]] $Values, $Label)
                [pscustomobject]@{
                    PolicyName       = [string]$policy.displayName
                    PolicyId         = [string]$policy.id
                    Source           = $source.Name
                    ODataType        = $oDataType
                    Property         = $Path
                    CategoryPath     = $category
                    Value            = $Values
                    ValueDisplayName = $Label
                }
            }
            $walk = {
                param($Object, $Prefix)
                foreach ($property in $Object.PSObject.Properties) {
                    # '@odata.type' and the like, nested too.
                    if ($property.Name -like '*@*' -or (-not $Prefix -and $property.Name -in $metadata)) { continue }
                    $path = if ($Prefix) { "$Prefix.$($property.Name)" } else { $property.Name }
                    $value = $property.Value
                    if ($null -eq $value) { continue }
                    if ($value -is [bool]) { if ($value) { & $setting $path @('true') 'Yes' } }
                    elseif ($value -is [string]) { if ($value -and $value -notin $defaults) { & $setting $path @($value) $value } }
                    elseif ($value -is [ValueType]) { & $setting $path @("$value") "$value" }
                    elseif ($value -is [System.Collections.IEnumerable]) {
                        $items = @($value | Where-Object { $null -ne $_ })
                        if (-not $items.Count) { continue }
                        if (@($items | Where-Object { $_ -isnot [string] -and $_ -isnot [ValueType] }).Count) { $leftOut.Add($path); continue }
                        $texts = @($items | ForEach-Object { "$_" })
                        & $setting $path $texts ($texts -join ', ')
                    } else { & $walk $value $path }
                }
            }
            & $walk $policy ''
            $actions = @($policy.scheduledActionsForRule | Where-Object { $_ } | ForEach-Object { $_.scheduledActionConfigurations } | Where-Object { $_ -and $_.actionType -ne 'noAction' })
            foreach ($kind in @($actions | Group-Object actionType)) {
                $hours = @($kind.Group | ForEach-Object { "$($_.gracePeriodHours)" } | Select-Object -Unique)
                & $setting "scheduledActionsForRule.scheduledActionConfigurations[actionType=$($kind.Name)].gracePeriodHours" $hours ($hours -join ', ')
            }
            if ($leftOut.Count) { Write-Warning "$($policy.displayName): left out $($leftOut -join ', '): a list of objects has no property path to test." }
        }
    }
}
