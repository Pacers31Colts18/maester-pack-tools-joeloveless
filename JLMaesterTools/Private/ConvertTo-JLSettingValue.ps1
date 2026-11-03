function ConvertTo-JLSettingValue {
    <#
    .SYNOPSIS
        Flattens a settings catalog settingInstance and its children into Id / Values / ParentId rows, as the pack
        helpers do. ParentId is the setting the row is nested under (empty at the top).
    #>
    [CmdletBinding()]
    param([AllowNull()] [object] $Instance, [string] $ParentId = '')

    if ($null -eq $Instance) { return }
    $values = @()
    $children = @()
    switch ($Instance.'@odata.type') {
        '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance' { $values = @($Instance.choiceSettingValue.value); $children = @($Instance.choiceSettingValue.children) }
        '#microsoft.graph.deviceManagementConfigurationChoiceSettingCollectionInstance' { $values = @($Instance.choiceSettingCollectionValue.value); $children = @($Instance.choiceSettingCollectionValue.children) }
        '#microsoft.graph.deviceManagementConfigurationSimpleSettingInstance' { $values = @($Instance.simpleSettingValue.value) }
        '#microsoft.graph.deviceManagementConfigurationSimpleSettingCollectionInstance' { $values = @($Instance.simpleSettingCollectionValue.value) }
        '#microsoft.graph.deviceManagementConfigurationGroupSettingInstance' { $children = @($Instance.groupSettingValue.children) }
        '#microsoft.graph.deviceManagementConfigurationGroupSettingCollectionInstance' { $children = @($Instance.groupSettingCollectionValue.children) }
    }
    $id = [string]$Instance.settingDefinitionId
    [pscustomobject]@{ Id = $id; Values = @($values | Where-Object { $null -ne $_ }); ParentId = $ParentId }
    foreach ($child in @($children | Where-Object { $null -ne $_ })) { ConvertTo-JLSettingValue -Instance $child -ParentId $id }
}
