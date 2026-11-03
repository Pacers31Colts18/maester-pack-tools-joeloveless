function Write-JLFrameworkFile {
    <#
    .SYNOPSIS
        Writes a framework file in the repository's layout: one key per line, then one requirement per line.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [object] $Framework
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('{')
    foreach ($property in $Framework.PSObject.Properties) {
        if ($property.Name -eq 'Requirements') { continue }
        $lines.Add("  $(ConvertTo-Json $property.Name -Compress): $(ConvertTo-Json $property.Value -Compress -Depth 5),")
    }
    $requirements = @($Framework.Requirements | Where-Object { $null -ne $_ })
    if ($requirements.Count -eq 0) {
        $lines.Add('  "Requirements": []')
    } else {
        $lines.Add('  "Requirements": [')
        for ($i = 0; $i -lt $requirements.Count; $i++) {
            $pairs = @($requirements[$i].PSObject.Properties | ForEach-Object { "$(ConvertTo-Json $_.Name -Compress): $(ConvertTo-Json $_.Value -Compress -Depth 5)" })
            $lines.Add("    { $($pairs -join ', ') }$(if ($i -lt $requirements.Count - 1) { ',' })")
        }
        $lines.Add('  ]')
    }
    $lines.Add('}')
    Write-JLTextFile -Path $Path -Text ($lines -join "`n")
}
