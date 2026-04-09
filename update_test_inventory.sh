#!/bin/bash
# update_test_inventory.sh
# Scans all AL test codeunits in ERP.CRE, generates:
#   1. al_test_inventory.csv  (detailed per-test-method rows)
#   2. al_test_inventory.xlsx (formatted Excel with Detail + Summary + Run Info sheets)
#
# Usage: ./update_test_inventory.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
CSV_FILE="$REPO_ROOT/al_test_inventory.csv"
XLSX_FILE="$REPO_ROOT/al_test_inventory.xlsx"

echo "Scanning AL test codeunits in $REPO_ROOT ..."

TEST_DIRS=(
  "$REPO_ROOT/extensions/Zig365-Commercial-Real-Estate-Foundation-Tests/src"
  "$REPO_ROOT/extensions/Zig365-Commercial-Real-Estate-Property-Management-Contracts-Tests/src"
  "$REPO_ROOT/extensions/Zig365-Commercial-Real-Estate-Property-Management-Contracts-Performance-Tests/src"
  "$REPO_ROOT/ERP.CRE/extensions/Zig365-Commercial-Real-Estate-Property-Management-Contracts-Tests/src"
  "$REPO_ROOT/ERP.CRE/extensions/Zig365-Commercial-Real-Estate-Foundation-Tests/src"
  "$REPO_ROOT/ERP.CRE/extensions/Zig365-Commercial-Real-Estate-Property-Management-Contracts-Performance-Tests/src"
)

PM_KEYWORDS="PropMan|PMBlanket|PMContract|Cluster|RealtyObject|Exploitation|RentBrokerage|CostCode|Element|LettableObj|Fee"

echo 'FilePath,CodeunitName,CodeunitID,TestMethod,TargetTables,TargetPages,WhatItValidates,IsPMRelated' > "$CSV_FILE"

total_tests=0
total_pm=0
total_files=0

for DIR in "${TEST_DIRS[@]}"; do
  [[ -d "$DIR" ]] || continue
  while IFS= read -r -d '' file; do
    grep -q '\[Test\]' "$file" 2>/dev/null || continue
    total_files=$((total_files + 1))

    rel_path="${file#$REPO_ROOT/}"
    codeunit_line=$(grep -m1 'codeunit [0-9]' "$file" || echo "")
    codeunit_id=$(echo "$codeunit_line" | grep -oE '[0-9]+' | head -1)
    codeunit_name=$(echo "$codeunit_line" | sed -E 's/.*codeunit [0-9]+ "?([^"]*)"?.*/\1/' | sed 's/ *$//')
    file_tests=$(grep -c '\[Test\]' "$file")
    total_tests=$((total_tests + file_tests))

    if grep -qEi "$PM_KEYWORDS" "$file"; then
      is_pm="Yes"
      total_pm=$((total_pm + file_tests))
    else
      is_pm="No"
    fi

    while IFS= read -r test_method; do
      method_name=$(echo "$test_method" | sed -E 's/.*procedure ([a-zA-Z0-9_]+).*/\1/')
      echo "\"$rel_path\",\"$codeunit_name\",$codeunit_id,\"$method_name\",\"\",\"\",\"\",\"$is_pm\"" >> "$CSV_FILE"
    done < <(grep -A1 '\[Test\]' "$file" | grep 'procedure ' || true)

  done < <(find "$DIR" -name "*.al" -print0 2>/dev/null)
done

echo ""
echo "=== Test Inventory Summary ==="
echo "Total test files:    $total_files"
echo "Total [Test] methods: $total_tests"
echo "PM-related tests:    $total_pm"
echo "Non-PM tests:        $((total_tests - total_pm))"
echo "CSV written to:      $CSV_FILE"

# ── Generate Excel ───────────────────────────────────────────────────
echo ""
echo "Generating Excel file..."
export REPO_ROOT

python3 << 'PYEOF'
import csv, os
from collections import defaultdict
from datetime import datetime
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.utils import get_column_letter

REPO_ROOT = os.environ["REPO_ROOT"]
CSV_FILE = os.path.join(REPO_ROOT, "al_test_inventory.csv")
XLSX_FILE = os.path.join(REPO_ROOT, "al_test_inventory.xlsx")

wb = Workbook()
header_font = Font(name="Calibri", bold=True, color="FFFFFF", size=11)
header_fill = PatternFill(start_color="2F5496", end_color="2F5496", fill_type="solid")
header_align = Alignment(horizontal="center", vertical="center", wrap_text=True)
cell_font = Font(name="Calibri", size=10)
cell_align = Alignment(vertical="top", wrap_text=True)
yes_fill = PatternFill(start_color="C6EFCE", end_color="C6EFCE", fill_type="solid")
no_fill = PatternFill(start_color="FFC7CE", end_color="FFC7CE", fill_type="solid")
mixed_fill = PatternFill(start_color="FFEB9C", end_color="FFEB9C", fill_type="solid")
summary_header_fill = PatternFill(start_color="1F4E79", end_color="1F4E79", fill_type="solid")
summary_total_fill = PatternFill(start_color="D6E4F0", end_color="D6E4F0", fill_type="solid")
thin_border = Border(left=Side(style="thin"), right=Side(style="thin"),
                     top=Side(style="thin"), bottom=Side(style="thin"))

# Sheet 1: Detail
ws = wb.active
ws.title = "Detail"
headers = ["FilePath","CodeunitName","CodeunitID","TestMethod","TargetTables","TargetPages","WhatItValidates","IsPMRelated"]
for ci, h in enumerate(headers, 1):
    c = ws.cell(row=1, column=ci, value=h)
    c.font, c.fill, c.alignment, c.border = header_font, header_fill, header_align, thin_border

rows = []
with open(CSV_FILE) as f:
    for r in csv.DictReader(f):
        rows.append(r)

for ri, r in enumerate(rows, 2):
    for ci, h in enumerate(headers, 1):
        c = ws.cell(row=ri, column=ci, value=r.get(h, ""))
        c.font, c.alignment, c.border = cell_font, cell_align, thin_border
        if ci == 8:
            c.fill = yes_fill if r.get(h) == "Yes" else no_fill if r.get(h) == "No" else PatternFill()

for i, w in enumerate([65,35,12,60,40,25,55,12], 1):
    ws.column_dimensions[get_column_letter(i)].width = w
ws.auto_filter.ref = ws.dimensions
ws.freeze_panes = "A2"

# Sheet 2: Summary
ws2 = wb.create_sheet("Summary")
cd = defaultdict(lambda: {"tests":0,"pm_yes":0,"pm_no":0,"id":""})
for r in rows:
    k = r["CodeunitName"]
    cd[k]["tests"] += 1; cd[k]["id"] = r["CodeunitID"]
    if r["IsPMRelated"] == "Yes": cd[k]["pm_yes"] += 1
    else: cd[k]["pm_no"] += 1

sc = sorted(cd.items(), key=lambda x: x[1]["tests"], reverse=True)
for ci, h in enumerate(["Codeunit","ID","Tests","PM?"], 1):
    c = ws2.cell(row=1, column=ci, value=h)
    c.font, c.fill, c.alignment, c.border = header_font, summary_header_fill, header_align, thin_border

tt, tp, tn = 0, 0, 0
for ri, (name, d) in enumerate(sc, 2):
    pm = "Mixed" if d["pm_yes"]>0 and d["pm_no"]>0 else "Yes" if d["pm_yes"]>0 else "No"
    vals = [name, int(d["id"]) if d["id"].isdigit() else d["id"], d["tests"], pm]
    tt += d["tests"]; tp += d["pm_yes"]; tn += d["pm_no"]
    for ci, v in enumerate(vals, 1):
        c = ws2.cell(row=ri, column=ci, value=v)
        c.font, c.border = cell_font, thin_border
        c.alignment = Alignment(horizontal="center" if ci>1 else "left", vertical="center")
        if ci == 4:
            c.fill = yes_fill if v=="Yes" else no_fill if v=="No" else mixed_fill

tr = len(sc) + 2
for ci, v in enumerate(["TOTAL","",tt,f"{tp} PM / {tn} Non-PM"], 1):
    c = ws2.cell(row=tr, column=ci, value=v)
    c.font = Font(name="Calibri", bold=True, size=11)
    c.fill, c.border = summary_total_fill, thin_border
    c.alignment = Alignment(horizontal="center" if ci>1 else "left", vertical="center")

for i, w in enumerate([40,10,10,20], 1):
    ws2.column_dimensions[get_column_letter(i)].width = w
ws2.freeze_panes = "A2"

# Sheet 3: Run Info
ws3 = wb.create_sheet("Run Info")
for ri, (l, v) in enumerate([
    ("Generated", datetime.now().strftime("%Y-%m-%d %H:%M")),
    ("Scope", "ERP.CRE"),
    ("Total Test Files", len(set(r["FilePath"] for r in rows))),
    ("Total [Test] Methods", tt),
    ("PM-Related Tests", tp),
    ("Non-PM Tests", tn),
    ("CSV Path", CSV_FILE),
    ("XLSX Path", XLSX_FILE),
], 1):
    c1 = ws3.cell(row=ri, column=1, value=l); c1.font = Font(name="Calibri", bold=True, size=11); c1.border = thin_border
    c2 = ws3.cell(row=ri, column=2, value=v); c2.font = cell_font; c2.border = thin_border
ws3.column_dimensions["A"].width = 22
ws3.column_dimensions["B"].width = 70

wb.save(XLSX_FILE)
print(f"Excel written to: {XLSX_FILE}")
PYEOF

echo ""
echo "=== Output Files ==="
echo "  CSV:   $CSV_FILE"
echo "  Excel: $XLSX_FILE"
echo ""
echo "Done."
