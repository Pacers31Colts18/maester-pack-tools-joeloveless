function Invoke-JLGraphGet {
    <#
    .SYNOPSIS
        A Graph GET through the connected Microsoft Graph session: the items of a collection (every page) or the object.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Uri)

    $response = Invoke-MgGraphRequest -Method GET -Uri $Uri -OutputType PSObject
    if ($null -eq $response.PSObject.Properties['value']) { return $response }
    $response.value
    while ($response.'@odata.nextLink') {
        $response = Invoke-MgGraphRequest -Method GET -Uri $response.'@odata.nextLink' -OutputType PSObject
        $response.value
    }
}
