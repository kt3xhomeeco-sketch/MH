# Script thêm sheet ColumnAliases vào CONFIG.xlsx
# Chạy 1 lần để tạo sheet, sau đó có thể chỉnh sửa trực tiếp trong Excel

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
        if ($sheet.Name -eq "ColumnAliases") {
            $sheetExists = $true
            Write-Host "Sheet 'ColumnAliases' already exists. Overwriting data..."
            $ws = $sheet
            $ws.Cells.Clear()
            break
        }
    }
    
    if (-not $sheetExists) {
        $ws = $wb.Worksheets.Add([System.Reflection.Missing]::Value, $wb.Worksheets($wb.Worksheets.Count))
        $ws.Name = "ColumnAliases"
        Write-Host "Created new sheet 'ColumnAliases'"
    }
    
    # Header row
    $ws.Cells(1, 1).Value2 = "internal_name"
    $ws.Cells(1, 2).Value2 = "alias"
    
    # Bold header
    $ws.Range("A1:B1").Font.Bold = $true
    $ws.Range("A1:B1").Interior.ColorIndex = 15  # Light gray
    
    # Data - Ma_SP aliases
    $aliases = @(
        @("Ma_SP", "Ma_SP"),
        @("Ma_SP", "Mã SP"),
        @("Ma_SP", "Ma SP"),
        @("Ma_SP", "MaSP"),
        @("Ma_SP", "Mã sản phẩm"),
        @("Ma_SP", "Ma san pham"),
        @("Ma_SP", "Product Code"),
        @("Ma_SP", "SP"),
        
        @("Ma_vat_lieu", "Ma_vat_lieu"),
        @("Ma_vat_lieu", "Mã vật liệu"),
        @("Ma_vat_lieu", "Ma vat lieu"),
        @("Ma_vat_lieu", "MaVL"),
        @("Ma_vat_lieu", "Mã VL"),
        @("Ma_vat_lieu", "Ma VL"),
        @("Ma_vat_lieu", "Material Code"),
        @("Ma_vat_lieu", "Material"),
        @("Ma_vat_lieu", "VL"),
        
        @("Ten_chi_tiet", "Ten_chi_tiet"),
        @("Ten_chi_tiet", "Tên chi tiết"),
        @("Ten_chi_tiet", "Ten chi tiet"),
        @("Ten_chi_tiet", "TenCT"),
        @("Ten_chi_tiet", "Chi tiết"),
        @("Ten_chi_tiet", "Chi tiet"),
        @("Ten_chi_tiet", "Detail Name"),
        @("Ten_chi_tiet", "Detail"),
        @("Ten_chi_tiet", "Tên CT")
    )
    
    $row = 2
    foreach ($item in $aliases) {
        $ws.Cells($row, 1).Value2 = $item[0]
        $ws.Cells($row, 2).Value2 = $item[1]
        $row++
    }
    
    # Color coding cho dễ phân biệt
    # Ma_SP rows -> light blue
    $ws.Range("A2:B9").Interior.Color = 0xFFF0D0  # Light blue (BGR)
    # Ma_vat_lieu rows -> light green
    $ws.Range("A10:B18").Interior.Color = 0xD0FFD0  # Light green (BGR)
    # Ten_chi_tiet rows -> light yellow
    $ws.Range("A19:B28").Interior.Color = 0xD0FFFF  # Light yellow (BGR)
    
    # Auto-fit columns
    $ws.Columns("A:B").AutoFit() | Out-Null
    
    $wb.Save()
    Write-Host ""
    Write-Host "SUCCESS: Added $($row - 2) aliases to sheet 'ColumnAliases'"
    Write-Host "You can now edit CONFIG.xlsx to add/remove aliases."
    Write-Host ""
    Write-Host "Format:"
    Write-Host "  Column A (internal_name): Ma_SP | Ma_vat_lieu | Ten_chi_tiet"
    Write-Host "  Column B (alias): ten cot ban muon nhan dien"
    
} catch {
    Write-Host "ERROR: $($_.Exception.Message)"
} finally {
    $wb.Close($false)
    $excel.Quit()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null
}
