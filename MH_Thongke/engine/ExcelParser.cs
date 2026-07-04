using System;
using System.IO;
using System.IO.Packaging;
using System.Xml;
using System.Collections.Generic;
using System.Text;
using System.Text.RegularExpressions;

namespace ExcelParser
{
    class Program
    {
        static void Main(string[] args)
        {
            if (args.Length < 1)
            {
                Console.WriteLine("[]");
                return;
            }

            string filePath = args[0];
            if (!File.Exists(filePath))
            {
                Console.WriteLine("[]");
                return;
            }

            try
            {
                List<string> sharedStrings = new List<string>();
                Dictionary<string, string> cellValues = new Dictionary<string, string>();

                using (Package package = Package.Open(filePath, FileMode.Open, FileAccess.Read))
                {
                    // 1. Get Shared Strings
                    Uri sharedStringsUri = new Uri("/xl/sharedStrings.xml", UriKind.Relative);
                    if (package.PartExists(sharedStringsUri))
                    {
                        PackagePart sharedStringsPart = package.GetPart(sharedStringsUri);
                        using (Stream stream = sharedStringsPart.GetStream())
                        using (XmlReader reader = XmlReader.Create(stream))
                        {
                            while (reader.Read())
                            {
                                if (reader.NodeType == XmlNodeType.Element && reader.LocalName == "t")
                                {
                                    sharedStrings.Add(reader.ReadElementContentAsString());
                                }
                            }
                        }
                    }

                    // 2. Read Sheet 1 (assume /xl/worksheets/sheet1.xml)
                    Uri sheetUri = new Uri("/xl/worksheets/sheet1.xml", UriKind.Relative);
                    if (!package.PartExists(sheetUri))
                    {
                        // Try to find the first sheet in relationships
                        sheetUri = null;
                        Uri workbookUri = new Uri("/xl/workbook.xml", UriKind.Relative);
                        if (package.PartExists(workbookUri))
                        {
                            PackagePart wbPart = package.GetPart(workbookUri);
                            foreach (PackageRelationship rel in wbPart.GetRelationshipsByType("http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet"))
                            {
                                sheetUri = PackUriHelper.ResolvePartUri(workbookUri, rel.TargetUri);
                                break;
                            }
                        }
                    }

                    if (sheetUri != null && package.PartExists(sheetUri))
                    {
                        PackagePart sheetPart = package.GetPart(sheetUri);
                        using (Stream stream = sheetPart.GetStream())
                        using (XmlReader reader = XmlReader.Create(stream))
                        {
                            string currentCell = "";
                            string cellType = "";
                            while (reader.Read())
                            {
                                if (reader.NodeType == XmlNodeType.Element && reader.LocalName == "c")
                                {
                                    currentCell = reader.GetAttribute("r");
                                    cellType = reader.GetAttribute("t");
                                }
                                else if (reader.NodeType == XmlNodeType.Element && reader.LocalName == "v" && !string.IsNullOrEmpty(currentCell))
                                {
                                    string val = reader.ReadElementContentAsString();
                                    if (cellType == "s" && int.TryParse(val, out int ssIndex) && ssIndex < sharedStrings.Count)
                                    {
                                        val = sharedStrings[ssIndex];
                                    }
                                    cellValues[currentCell] = val;
                                    currentCell = "";
                                }
                                else if (reader.NodeType == XmlNodeType.Element && reader.LocalName == "is" && !string.IsNullOrEmpty(currentCell))
                                {
                                    // Inline string
                                    using (XmlReader inner = reader.ReadSubtree())
                                    {
                                        string val = "";
                                        while (inner.Read())
                                        {
                                            if (inner.NodeType == XmlNodeType.Element && inner.LocalName == "t")
                                            {
                                                val += inner.ReadElementContentAsString();
                                            }
                                        }
                                        cellValues[currentCell] = val;
                                    }
                                    currentCell = "";
                                }
                            }
                        }
                    }
                }

                // Process the cells into 2D array
                int maxRow = 0;
                int maxCol = 0;
                foreach (string cr in cellValues.Keys)
                {
                    ParseCellReference(cr, out int r, out int c);
                    if (r > maxRow) maxRow = r;
                    if (c > maxCol) maxCol = c;
                }

                string[,] table = new string[maxRow + 1, maxCol + 1];
                foreach (var kvp in cellValues)
                {
                    ParseCellReference(kvp.Key, out int r, out int c);
                    table[r, c] = kvp.Value;
                }

                // 3. Find Header Row
                int headerRow = 7;
                int ma_sp_col = 9, ten_sp_col = 10, quy_cach_col = 5, chi_tiet_col = 6, hoan_thien_col = 7, ma_vl_col = 11, ghi_chu_col = -1;
                
                for (int r = 1; r <= Math.Min(15, maxRow); r++)
                {
                    bool found_ma_sp = false;
                    bool found_quy_cach = false;
                    bool found_hoan_thien = false;

                    for (int c = 1; c <= Math.Min(30, maxCol); c++)
                    {
                        string raw = table[r, c] ?? "";
                        if (string.IsNullOrEmpty(raw) || raw.Length > 40) continue;

                        string norm = Regex.Replace(RemoveDiacritics(raw).ToLower(), @"\s+", " ").Trim();
                        string compact = norm.Replace(" ", "");
                        string header_key = Regex.Replace(norm, @"[^a-z0-9]+", "");

                        if (header_key == "masp") { ma_sp_col = c; found_ma_sp = true; }
                        if (header_key == "tensp" || header_key == "tensanpham") { ten_sp_col = c; }
                        if (norm.Contains("quy cach")) { quy_cach_col = c; found_quy_cach = true; }
                        if (norm.Contains("hoan thien")) { hoan_thien_col = c; found_hoan_thien = true; }
                        if (header_key == "mavatlieu" || header_key == "mavl") { ma_vl_col = c; }
                        if (header_key == "ghichu" || compact == "note" || compact == "notes") { ghi_chu_col = c; }
                    }

                    if (found_ma_sp && (found_quy_cach || found_hoan_thien))
                    {
                        headerRow = r;
                        break;
                    }
                }

                // 4. Extract Data
                StringBuilder json = new StringBuilder();
                json.Append("[\n");
                int emptyCount = 0;
                bool first = true;

                for (int r = headerRow + 1; r <= maxRow; r++)
                {
                    string ma_sp = (table[r, ma_sp_col] ?? "").Trim();
                    if (string.IsNullOrEmpty(ma_sp))
                    {
                        emptyCount++;
                        if (emptyCount >= 10) break;
                        continue;
                    }
                    emptyCount = 0;

                    string ma_vl = (table[r, ma_vl_col] ?? "").Trim();
                    if (string.IsNullOrEmpty(ma_vl)) // only accessories
                    {
                        string hw_name = (table[r, quy_cach_col] ?? "").Trim();
                        string spec = (table[r, hoan_thien_col] ?? "").Trim();
                        string ten_sp = (table[r, ten_sp_col] ?? "").Trim();
                        string chi_tiet = (table[r, chi_tiet_col] ?? "").Trim();
                        string ghi_chu = ghi_chu_col > 0 ? (table[r, ghi_chu_col] ?? "").Trim() : "";

                        if (!first) json.Append(",\n");
                        first = false;
                        
                        json.Append("  {\n");
                        json.AppendFormat("    \"ma_sp\": \"{0}\",\n", EscapeJson(ma_sp.ToUpper()));
                        json.AppendFormat("    \"ten_sp\": \"{0}\",\n", EscapeJson(ten_sp));
                        json.AppendFormat("    \"hw_name\": \"{0}\",\n", EscapeJson(hw_name));
                        json.AppendFormat("    \"spec\": \"{0}\",\n", EscapeJson(spec));
                        json.AppendFormat("    \"ghi_chu\": \"{0}\",\n", EscapeJson(ghi_chu));
                        json.AppendFormat("    \"excel_col6\": \"{0}\"\n", EscapeJson(chi_tiet));
                        json.Append("  }");
                    }
                }
                json.Append("\n]");

                if (args.Length > 1)
                {
                    File.WriteAllText(args[1], json.ToString(), Encoding.UTF8);
                }
                else
                {
                    Console.WriteLine(json.ToString());
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine("[]"); // Silently fail and return empty array
            }
        }

        static void ParseCellReference(string cr, out int r, out int c)
        {
            r = 0; c = 0;
            if (string.IsNullOrEmpty(cr)) return;
            int i = 0;
            while (i < cr.Length && char.IsLetter(cr[i]))
            {
                c = c * 26 + (char.ToUpper(cr[i]) - 'A' + 1);
                i++;
            }
            if (i < cr.Length)
            {
                int.TryParse(cr.Substring(i), out r);
            }
        }

        static string RemoveDiacritics(string text)
        {
            if (string.IsNullOrEmpty(text)) return text;
            var normalizedString = text.Normalize(NormalizationForm.FormD);
            var stringBuilder = new StringBuilder();

            foreach (var c in normalizedString)
            {
                var unicodeCategory = System.Globalization.CharUnicodeInfo.GetUnicodeCategory(c);
                if (unicodeCategory != System.Globalization.UnicodeCategory.NonSpacingMark)
                {
                    stringBuilder.Append(c);
                }
            }

            return stringBuilder.ToString().Normalize(NormalizationForm.FormC).Replace('đ', 'd').Replace('Đ', 'D');
        }

        static string EscapeJson(string str)
        {
            if (string.IsNullOrEmpty(str)) return "";
            return str.Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\n", "\\n").Replace("\r", "");
        }
    }
}
