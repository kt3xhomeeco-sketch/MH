$configFile = Join-Path $PSScriptRoot "CONFIG.xlsx"

if (-not (Test-Path $configFile)) {
    Write-Host "ERROR: CONFIG.xlsx not found at $configFile"
    exit 1
}

$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$excel.DisplayAlerts = $false

try {
    $wb = $excel.Workbooks.Open($configFile)
    
    # Kiểm tra sheet đã tồn tại chưa
    $sheetExists = $false
    foreach ($sheet in $wb.Worksheets) {
        if ($sheet.Name -eq "InvalidMaterials") {
            $sheetExists = $true
            Write-Host "Sheet 'InvalidMaterials' already exists. Overwriting data..."
            $ws = $sheet
            $ws.Cells.Clear()
            break
        }
    }
    
    if (-not $sheetExists) {
        $ws = $wb.Worksheets.Add([System.Reflection.Missing]::Value, $wb.Worksheets($wb.Worksheets.Count))
        $ws.Name = "InvalidMaterials"
        Write-Host "Created new sheet 'InvalidMaterials'"
    }
    
    # Header row
    $ws.Cells(1, 1).Value2 = "Ma_vat_lieu"
    $ws.Cells(1, 2).Value2 = "Do_day"
    
    # Bold header
    $ws.Range("A1:B1").Font.Bold = $true
    $ws.Range("A1:B1").Interior.ColorIndex = 15  # Light gray
    
    # Example data
    $ws.Cells(2, 1).Value2 = "PICOMAT"
    $ws.Cells(2, 2).Value2 = "17"
    
    # Auto-fit columns
    $ws.Columns("A:B").AutoFit() | Out-Null
    
    $wb.Save()
    Write-Host "SUCCESS: Added sheet 'InvalidMaterials' with sample data (PICOMAT, 17)"
    
} catch {
    Write-Host "ERROR: $($_.Exception.Message)"
} finally {
    $wb.Close($false)
    $excel.Quit()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null
}
