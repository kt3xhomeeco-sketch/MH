"""Shared purchase-name engine, reading the existing material_code_library.xlsx.

Only the Python standard library is required, including when called by SketchUp.
The workbook is read-only; both callers use the same file and matching rules.
"""

import json
import re
import sys
import unicodedata
import xml.etree.ElementTree as ET
from pathlib import Path
from zipfile import ZipFile

NS = {"s": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
# Compatibility for older SketchUp codes. Explicit workbook entries win.
ALIASES = {"LK": "LAM", "LAM": "LK", "MS": "MEL", "MEL": "MS",
           "GOTN": "GTN", "GTN": "GOTN", "GGTHANH": "GGT", "GGT": "GGTHANH"}
NAME_GROUPS = ("chat_lieu", "tieu_chuan", "nha_cung_cap", "be_mat")
FACE = re.compile(r"([12]M)(?:-(BCT|BCĐ|BCD))?", re.IGNORECASE)
BACKER = re.compile(r"-(BCT|BCĐ|BCD)$", re.IGNORECASE)
_cached = None


def workbook_rows(path, sheet_name):
    """Read the requested sheet without rewriting any part of the workbook."""
    with ZipFile(path) as archive:
        shared = []
        if "xl/sharedStrings.xml" in archive.namelist():
            root = ET.fromstring(archive.read("xl/sharedStrings.xml"))
            shared = ["".join(n.text or "" for n in node.findall(".//s:t", NS))
                      for node in root.findall("s:si", NS)]
        book = ET.fromstring(archive.read("xl/workbook.xml"))
        sheets = book.findall("s:sheets/s:sheet", NS)
        sheet = next((s for s in sheets if s.get("name", "").lower() == sheet_name.lower()), None)
        if sheet is None:
            raise ValueError(f"Không có sheet {sheet_name!r} trong {path}")
        rel_id = sheet.get("{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id")
        rels = ET.fromstring(archive.read("xl/_rels/workbook.xml.rels"))
        target = next(r.get("Target") for r in rels if r.get("Id") == rel_id)
        xml_path = target.lstrip("/") if target.startswith("/") else "xl/" + target
        root = ET.fromstring(archive.read(xml_path))
        for row in root.findall("s:sheetData/s:row", NS):
            values = {}
            for cell in row.findall("s:c", NS):
                column = re.match(r"[A-Z]+", cell.get("r", "")).group()
                index = 0
                for letter in column:
                    index = index * 26 + ord(letter) - ord("A") + 1
                value = cell.find("s:v", NS)
                text = value.text if value is not None else ""
                if cell.get("t") == "s":
                    text = shared[int(text)]
                elif cell.get("t") == "inlineStr":
                    text = "".join(n.text or "" for n in cell.findall("s:is//s:t", NS))
                values[index - 1] = text or ""
            if values:
                yield [values.get(i, "") for i in range(max(values) + 1)]


def key(value):
    return re.sub(r"\s+", "", str(value).strip().upper())


def material_code_size(material_code, fallback=""):
    """Nominal thickness after the family; never infer it from E1 or a finish."""
    if "&" in str(material_code):
        return fallback
    match = re.match(r"^[^.&\s]+\.(\d+(?:[.,]\d+)?)(?=\.|$)", str(material_code).strip())
    if not match or float(match[1].replace(",", ".")) <= 0:
        return fallback
    whole, _, fraction = match[1].replace(",", ".").partition(".")
    whole = whole.lstrip("0") or "0"
    fraction = fraction.rstrip("0")
    return f"{whole}.{fraction}" if fraction else whole


def fold(value):
    text = str(value).strip().lower().replace("đ", "d").replace("_", " ")
    text = "".join(c for c in unicodedata.normalize("NFD", text)
                   if unicodedata.category(c) != "Mn")
    return " ".join(text.split())


class MaterialNames:
    def __init__(self, config_path):
        self.config_path = Path(config_path)
        rows = list(workbook_rows(self.config_path, "mapping"))
        aliases = {
            "name": ("tu khoa trong excel", "gia tri", "raw value", "input"),
            "code": ("ma tao ra", "gia tri map", "mapping", "ma map"),
            "group": ("nhom", "group"),
            "enabled": ("dang dung", "enabled", "active")
        }
        columns = None
        for header_index, row in enumerate(rows[:20]):
            headers = [fold(h) for h in row]
            candidate = {k: next((i for i, h in enumerate(headers) if h in names), None)
                         for k, names in aliases.items()}
            if all(candidate[k] is not None for k in ("name", "code", "group")):
                columns = candidate
                break
        if columns is None:
            raise ValueError(f"Sheet mapping cần các cột Từ khóa trong Excel, Mã tạo ra, Nhóm: {config_path}")
        self.groups = {group: {} for group in NAME_GROUPS}
        self.by_code = {}
        for row in rows[header_index + 1:]:
            def value(column):
                index = columns[column]
                return str(row[index]).strip() if index is not None and index < len(row) else ""

            if fold(value("enabled")) in ("0", "false", "no", "off", "khong", "disabled"):
                continue
            code, name = key(value("code")), value("name")
            group = fold(value("group")).replace(" ", "_")
            if not code or not name or group not in self.groups:
                continue
            # Multiple Excel input synonyms can create one code. The first
            # active row supplies its display name, as the old MH_EXPORT did.
            self.groups[group].setdefault(code, name)
            self.by_code.setdefault(code, name)
        if not self.by_code:
            raise ValueError(f"Bảng mã không có tên hàng hợp lệ: {config_path}")
        self.separator = "."
        try:
            for row in workbook_rows(self.config_path, "material_code_rules"):
                if len(row) > 1 and fold(row[0]) in ("dau ghep cac phan", "segment separator", "segment separator char"):
                    self.separator = row[1].strip() or "."
        except ValueError:
            # Older libraries without this optional sheet use the standard dot.
            pass

    def backer_name(self, code):
        canonical = "BCT" if code.upper() == "BCT" else "BCĐ"
        aliases = (canonical,) if canonical == "BCT" else ("BCĐ", "BCD")
        for alias in aliases:
            if alias in self.by_code:
                return self.by_code[alias]
            for face in ("1M", "2M"):
                combined = self.by_code.get(f"{face}-{alias}", "")
                label = self.by_code.get(face, f"{face[0]} mặt")
                if combined.upper().startswith(label.upper()):
                    remainder = combined[len(label):].strip(" -–—")
                    if remainder:
                        return remainder
        return "backer trắng" if canonical == "BCT" else "backer đen"

    def qualifiers(self, material_code):
        faces, backers, segments = [], [], []
        for segment in str(material_code).strip().split(self.separator):
            segment = segment.strip()
            face = FACE.fullmatch(segment)
            if face:
                token = face[1].upper()
                faces.append(self.by_code.get(token, f"{token[0]} mặt"))
                if face[2]:
                    backers.append(self.backer_name(face[2]))
                continue
            backer = BACKER.search(segment)
            if backer:
                backers.append(self.backer_name(backer[1]))
                segment = segment[:backer.start()]
            if segment:
                segments.append(segment)
        return self.separator.join(segments), list(dict.fromkeys(faces + backers))

    def name(self, material_code):
        base, qualifiers = self.qualifiers(material_code)
        tokens = [key(s) for s in base.split(self.separator) if s.strip()]
        tokens = [ALIASES.get(t, t) if t not in self.by_code and ALIASES.get(t) in self.by_code
                  else t for t in tokens]
        names = []
        for group in NAME_GROUPS:
            name = next((self.groups[group][token] for token in tokens if token in self.groups[group]), "")
            if not name:
                continue
            if group == "be_mat" and re.match(r"(?:Melamine|Laminate|Veneer)(?:\s|$)", name, re.IGNORECASE):
                name = "phủ " + name
            # A material name may already contain its supplier.
            candidate = set(re.findall(r"[^\W_]+", name.upper(), re.UNICODE))
            if any(candidate <= set(re.findall(r"[^\W_]+", n.upper(), re.UNICODE)) for n in names):
                continue
            names.append(name)
        if not names:
            names.append(f"Ván {base}".strip())
        names.extend(qualifiers)
        return " ".join(names).strip().upper()


def load_library(config_path=None):
    global _cached
    path = Path(config_path) if config_path else Path(__file__).with_name("material_code_library.xlsx")
    stat = path.stat()
    signature = (str(path.resolve()), stat.st_mtime_ns, stat.st_size)
    if _cached is None or _cached[0] != signature:
        _cached = (signature, MaterialNames(path))
    return _cached[1]


def main():
    # UTF-8 is explicit so Vietnamese survives SketchUp's Windows subprocess pipes.
    sys.stdin.reconfigure(encoding="utf-8")
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    try:
        request = json.load(sys.stdin)
        library = load_library(request.get("config_path"))
        codes = request.get("codes", [])
        result = {"names": {code: library.name(code) for code in codes}}
        if "qualifier_code" in request:
            result["qualifiers"] = library.qualifiers(request["qualifier_code"])
        print(json.dumps(result, ensure_ascii=False))
        return 0
    except Exception as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
