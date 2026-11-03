function Write-JLTextFile {
    <#
    .SYNOPSIS
        Writes text as UTF-8 without a BOM, with LF line endings and one final newline; creates the folder if needed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Text
    )

    $folder = Split-Path -Parent $Path
    if ($folder -and -not (Test-Path -LiteralPath $folder)) { New-Item -ItemType Directory -Path $folder -Force | Out-Null }
    $normalized = ($Text -replace "`r`n", "`n").TrimEnd("`n") + "`n"
    [System.IO.File]::WriteAllText($Path, $normalized, [System.Text.UTF8Encoding]::new($false))
}
