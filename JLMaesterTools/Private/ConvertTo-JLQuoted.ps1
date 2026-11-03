function ConvertTo-JLQuoted {
    <#
    .SYNOPSIS
        A string as a PowerShell single-quoted literal, for the constant values of a test file.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Text)

    "'" + $Text.Replace("'", "''") + "'"
}
