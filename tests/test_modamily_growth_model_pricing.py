import os
import unittest
from pathlib import Path

from openpyxl import load_workbook


SOURCE_PATH = Path(
    "/Users/ivanfatovic/Claude-Work/Outputs/modamily-growth-model.xlsx"
)
OUTPUT_PATH = Path(
    "/Users/ivanfatovic/Claude-Work/Outputs/"
    "modamily-growth-model-pricing-launch-2026-08-16.xlsx"
)

EXPECTED_SCORECARD_HEADERS = [
    "Week ending",
    "Platform",
    "Pricing cohort",
    "Gross cash collected ($)",
    "Refunds ($)",
    "Fees ($)",
    "Net cash ($)",
    "Normalized new MRR ($)",
    "Active payers",
    "Eligible paywall viewers",
    "Paywall views",
    "Paid starts",
    "Weekly starts",
    "Monthly starts",
    "Quarterly starts",
    "Annual starts",
    "U.S. paid starts",
    "Non-U.S. paid starts",
    "Country unknown",
    "Net revenue / eligible viewer ($)",
    "28d rolling net cash ($)",
    "On track vs cash target?",
]


def normalized_formula(cell_ref):
    return str(cell_ref).replace(" ", "").upper()


class PricingLaunchWorkbookTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        selected = os.environ.get("MODAMILY_MODEL_PATH", str(OUTPUT_PATH))
        cls.path = Path(selected)
        if not cls.path.exists():
            raise AssertionError(f"Workbook does not exist: {cls.path}")
        # Formula strings and cached values cannot be obtained from one load.
        cls.formulas = load_workbook(cls.path, data_only=False)
        cls.values = load_workbook(cls.path, data_only=True)

    @classmethod
    def tearDownClass(cls):
        cls.formulas.close()
        cls.values.close()

    def test_pricing_ladder_uses_corrected_payer_mix_and_legacy_row(self):
        ws = self.formulas["Pricing Ladder"]
        self.assertEqual(
            [ws.cell(row=row, column=1).value for row in range(5, 10)],
            [
                "Annual (12m)",
                "Quarterly (3m)",
                "Monthly (1m)",
                "Weekly (1w)",
                "Legacy",
            ],
        )
        self.assertEqual(
            [ws.cell(row=row, column=7).value for row in range(5, 10)],
            [0.38, 0.27, 0.23, 0.08, 0.04],
        )
        self.assertAlmostEqual(ws["D9"].value, 32.0, places=6)

    def test_new_plan_mix_normalizes_to_one_and_excludes_legacy(self):
        formula_ws = self.formulas["Pricing Ladder"]
        value_ws = self.values["Pricing Ladder"]
        for row in range(5, 9):
            self.assertTrue(
                str(formula_ws.cell(row=row, column=8).value).startswith("="),
                f"H{row} must be a formula",
            )
        self.assertIsNone(formula_ws["H9"].value)
        self.assertAlmostEqual(
            sum(value_ws.cell(row=row, column=8).value for row in range(5, 9)),
            1.0,
            places=10,
        )

    def test_new_ladder_blended_arpu_excludes_legacy(self):
        ws = self.formulas["Pricing Ladder"]
        self.assertEqual(
            normalized_formula(ws["E13"].value),
            "=SUMPRODUCT(E5:E8,H5:H8)",
        )
        self.assertAlmostEqual(self.values["Pricing Ladder"]["E13"].value, 35.1654, places=4)

    def test_path_to_30k_is_explicitly_normalized_mrr(self):
        ws = self.formulas["Path to $30K"]
        self.assertEqual(
            normalized_formula(ws["D8"].value),
            "='PRICINGLADDER'!$E$13",
        )
        self.assertIn("normalized MRR", str(ws["A1"].value))
        self.assertIn("normalized", str(ws["E8"].value).lower())

    def test_weekly_scorecard_has_exact_launch_headers(self):
        ws = self.formulas["Weekly Scorecard"]
        self.assertEqual(
            [ws.cell(row=4, column=column).value for column in range(1, 23)],
            EXPECTED_SCORECARD_HEADERS,
        )

    def test_weekly_scorecard_uses_cash_formulas(self):
        ws = self.formulas["Weekly Scorecard"]
        self.assertEqual(normalized_formula(ws["G5"].value), "=D5-E5-F5")
        self.assertEqual(normalized_formula(ws["T5"].value), "=IFERROR(G5/J5,0)")
        self.assertEqual(
            normalized_formula(ws["U5"].value),
            '=SUMIFS($G:$G,$B:$B,B5,$A:$A,">="&A5-27,$A:$A,"<="&A5)',
        )
        self.assertEqual(
            normalized_formula(ws["V5"].value),
            '=IF(U5>=ASSUMPTIONS!$B$20,"YES","NO")',
        )
        self.assertTrue(str(ws["T5"].value).startswith("="))
        self.assertIn("cash", str(ws["A1"].value).lower())

    def test_payer_mix_source_and_annual_uncertainty_are_documented(self):
        ws = self.formulas["Pricing Ladder"]
        comments = " ".join(
            cell.comment.text for row in ws.iter_rows() for cell in row if cell.comment
        ).lower()
        self.assertIn("june 2", comments)
        self.assertIn("august 2", comments)
        self.assertIn("four annual charges", comments)
        self.assertIn("wide estimate", comments)
        cautions = " ".join(
            str(ws.cell(row=row, column=1).value or "") for row in range(16, 24)
        ).lower()
        self.assertNotIn("the price change is the arpu lever", cautions)
        self.assertIn("prepaid cash", cautions)

    def test_formula_cells_have_cached_values_after_recalculation(self):
        for sheet_name, refs in {
            "Pricing Ladder": ["H5", "H6", "H7", "H8", "E13"],
            "Path to $30K": ["D8", "D13"],
            "Weekly Scorecard": ["G5", "T5", "U5", "V5"],
        }.items():
            cached = self.values[sheet_name]
            for ref in refs:
                self.assertIsNotNone(cached[ref].value, f"{sheet_name}!{ref} lacks cached value")

    def test_formulas_outside_named_sheets_are_preserved(self):
        if self.path.resolve() == SOURCE_PATH.resolve():
            self.skipTest("preservation comparison applies to transformed output")
        source = load_workbook(SOURCE_PATH, data_only=False)
        try:
            named = {"Pricing Ladder", "Path to $30K", "Weekly Scorecard"}
            for sheet_name in source.sheetnames:
                if sheet_name in named:
                    continue
                before = {
                    cell.coordinate: cell.value
                    for row in source[sheet_name].iter_rows()
                    for cell in row
                    if cell.data_type == "f"
                }
                after = {
                    cell.coordinate: cell.value
                    for row in self.formulas[sheet_name].iter_rows()
                    for cell in row
                    if cell.data_type == "f"
                }
                self.assertEqual(after, before, f"formulas changed on {sheet_name}")
        finally:
            source.close()


if __name__ == "__main__":
    unittest.main()
