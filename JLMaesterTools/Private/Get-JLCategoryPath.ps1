function Get-JLCategoryPath {
    <#
    .SYNOPSIS
        The settings catalog category of a setting as 'Parent > Child', from configurationCategories; cached per session.
        Empty when the category cannot be read.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowEmptyString()] [string] $CategoryId)

    if (-not $CategoryId) { return '' }
    if ($null -eq $script:JLCategoryCache) { $script:JLCategoryCache = @{} }
    $names = [System.Collections.Generic.List[string]]::new()
    $id = $CategoryId
    for ($depth = 0; $id -and $depth -lt 6; $depth++) {
        if (-not $script:JLCategoryCache.ContainsKey($id)) {
            try { $script:JLCategoryCache[$id] = Invoke-JLGraphGet -Uri "beta/deviceManagement/configurationCategories('$id')" }
            catch { $script:JLCategoryCache[$id] = $null }
        }
        $category = $script:JLCategoryCache[$id]
        if (-not $category) { break }
        if ($category.displayName) { $names.Insert(0, [string]$category.displayName) }
        $parent = [string]$category.parentCategoryId
        # The root is part of the path, as Intune shows it (Administrative Templates > Control Panel > Personalization).
        if (-not $parent -or $parent -eq $id -or $parent -match '^0{8}-') { break }
        $id = $parent
    }
    $names -join ' > '
}
