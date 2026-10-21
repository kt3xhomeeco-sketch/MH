import sys
import json
import re
from pathlib import Path
import openpyxl

def remove_diacritics(text):
    if not text:
        return ""
    import unicodedata
    normalized = unicodedata.normalize('NFD', text)
    result = ''.join(c for c in normalized if unicodedata.category(c) != 'Mn')
    return result.replace('đ', 'd').replace('Đ', 'D')

def split_material_codes(code):
    if not code:
        return []
    import re
    # split by comma, semicolon, slash, etc.
    parts = re.split(r'[,;/\+&]', code)
    return [p.strip().upper() for p in parts if p.strip()]

def main():
    if len(sys.argv) < 2:
        print("[]")
        return
        
    file_path = sys.argv[1]
    if not Path(file_path).exists():
        print("[]")
        return
        
    try:
        wb = openpyxl.load_workbook(file_path, data_only=True, read_only=True)
        ws = wb.worksheets[0]
        
        table = []
        max_col = 0
        for row in ws.iter_rows(values_only=True):
            if row:
                max_col = max(max_col, len(row))
                table.append([str(cell).strip() if cell is not None else "" for cell in row])
                
        header_row_idx = 6 # 0-indexed, default is row 7
        ma_sp_col = 8
        ten_sp_col = 9
        quy_cach_col = 4
        chi_tiet_col = 5
        hoan_thien_col = 6
        ma_vl_col = 10
        ghi_chu_col = -1
        
        for r_idx, row in enumerate(table[:15]):
            found_ma_sp = False
            found_quy_cach = False
            found_hoan_thien = False
            
            for c_idx, val in enumerate(row[:30]):
                if not val or len(val) > 40:
                    continue
                
                norm = re.sub(r'\s+', ' ', remove_diacritics(val).lower()).strip()
                compact = norm.replace(" ", "")
                header_key = re.sub(r'[^a-z0-9]+', '', norm)
                
                if header_key == "masp":
                    ma_sp_col = c_idx
                    found_ma_sp = True
                elif header_key in ["tensp", "tensanpham"]:
                    ten_sp_col = c_idx
                elif "quy cach" in norm:
                    quy_cach_col = c_idx
                    found_quy_cach = True
                elif "hoan thien" in norm:
                    hoan_thien_col = c_idx
                    found_hoan_thien = True
                elif header_key in ["mavatlieu", "mavl"]:
                    ma_vl_col = c_idx
                elif header_key == "ghichu" or compact in ["note", "notes"]:
                    ghi_chu_col = c_idx
                    
            if found_ma_sp and (found_quy_cach or found_hoan_thien):
                header_row_idx = r_idx
                break
                
        result = []
        empty_count = 0
        
        for r_idx in range(header_row_idx + 1, len(table)):
            row = table[r_idx]
            
            ma_sp = row[ma_sp_col] if ma_sp_col < len(row) else ""
            if not ma_sp:
                empty_count += 1
                if empty_count >= 10:
                    break
                continue
            empty_count = 0
            
            ma_vl = row[ma_vl_col] if ma_vl_col < len(row) else ""
            hw_name = row[quy_cach_col] if quy_cach_col < len(row) else ""
            spec = row[hoan_thien_col] if hoan_thien_col < len(row) else ""
            ten_sp = row[ten_sp_col] if ten_sp_col < len(row) else ""
            chi_tiet = row[chi_tiet_col] if chi_tiet_col < len(row) else ""
            ghi_chu = row[ghi_chu_col] if ghi_chu_col >= 0 and ghi_chu_col < len(row) else ""
            
            if not ma_vl: # PK
                if hw_name:
                    result.append({
                        "ma_sp": ma_sp.upper(),
                        "ten_sp": ten_sp,
                        "hw_name": hw_name,
                        "spec": spec,
                        "ghi_chu": ghi_chu,
                        "excel_col6": chi_tiet,
                        "display_sub_parts": [hw_name, chi_tiet, spec],
                        "kind": "PK"
                    })
            else: # VL
                mat_codes = split_material_codes(ma_vl)
                for mat_name in mat_codes:
                    combined_spec = " ".join([hw_name, spec]).strip()
                    result.append({
                        "ma_sp": ma_sp.upper(),
                        "ten_sp": ten_sp,
                        "hw_name": mat_name,
                        "spec": combined_spec,
                        "ghi_chu": ghi_chu,
                        "excel_col6": chi_tiet,
                        "display_sub_parts": [mat_name, hw_name, chi_tiet, spec],
                        "ma_vl": mat_name,
                        "ma_vl_source": ma_vl,
                        "kind": "VL"
                    })
                
        json_output = json.dumps(result, ensure_ascii=False, indent=2)
        if len(sys.argv) > 2:
            with open(sys.argv[2], 'w', encoding='utf-8') as f:
                f.write(json_output)
        else:
            print(json_output)
            
    except Exception as e:
        print("[]")

if __name__ == "__main__":
    main()
