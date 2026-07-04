$file = Get-ChildItem "$PSScriptRoot\CONFIG.xlsx"
$filePath = $file.FullName
Write-Host "File: $filePath"
Write-Host "Size: $($file.Length) bytes"

$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$excel.DisplayAlerts = $false
$wb = $excel.Workbooks.Open($filePath)

Write-Host "=== Sheets: $($wb.Worksheets.Count) ==="
for ($s = 1; $s -le $wb.Worksheets.Count; $s++) {
    $sheet = $wb.Worksheets($s)
    $rows = $sheet.UsedRange.Rows.Count
    $cols = $sheet.UsedRange.Columns.Count
    Write-Host ""
    Write-Host "--- Sheet $s : '$($sheet.Name)' ($rows rows x $cols cols) ---"
    
    for ($r = 1; $r -le [Math]::Min(20, $rows); $r++) {
        $line = ""
        for ($c = 1; $c -le [Math]::Min(10, $cols); $c++) {
            $v = $sheet.Cells($r, $c).Value2
            if ($v) {
                $line += "[$c]$v | "
            }
        }
        if ($line) {
            Write-Host "  Row $r : $line"
        }
    }
}

$wb.Close($false)
$excel.Quit()
