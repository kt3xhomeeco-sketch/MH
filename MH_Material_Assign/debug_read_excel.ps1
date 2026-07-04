$files = Get-ChildItem "D:\Cong viec\2026\15*\SPEC\*.xlsx" -ErrorAction SilentlyContinue
if ($files.Count -eq 0) {
    Write-Host "No xlsx files found"
    exit 1
}

$filePath = $files[0].FullName
Write-Host "File: $filePath"
Write-Host "Size: $($files[0].Length) bytes"
Write-Host ""

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
    Write-Host "--- Sheet $s : '$($sheet.Name)' [$rows rows x $cols cols] ---"
    
    for ($r = 1; $r -le [Math]::Min(15, $rows); $r++) {
        $line = ""
        for ($c = 1; $c -le [Math]::Min(20, $cols); $c++) {
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
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null
