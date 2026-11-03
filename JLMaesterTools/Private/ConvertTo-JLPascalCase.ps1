function ConvertTo-JLPascalCase {
    <#
    .SYNOPSIS
        Letters and digits of a text in PascalCase, such as 'Allow Cortana Above Lock' to 'AllowCortanaAboveLock'.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [string] $Text)

    (@($Text -split '[^A-Za-z0-9]+' | Where-Object { $_ } | ForEach-Object { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1) })) -join ''
}
