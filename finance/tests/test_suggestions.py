"""Synthetic data only: no personal journal or bank exports in the repository."""

import contextlib
import csv
import io
import sys
import tempfile
import unittest
import zipfile
from datetime import date
from decimal import Decimal
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / ".local/bin"))
import bank_import
import bank_suggest
import bank_workflow


def history_csv(postings):
    output = io.StringIO()
    writer = csv.DictWriter(output, fieldnames=("txnidx", "date", "description", "account", "amount", "commodity"))
    writer.writeheader()
    writer.writerows(postings)
    return output.getvalue()


def posting(index, description, account, amount, currency="EUR"):
    return {"txnidx": str(index), "date": "2026-10-01", "description": description,
            "account": account, "amount": str(amount), "commodity": currency}


class SuggestionsTest(unittest.TestCase):
    def test_text_currency_only_if_unambiguous(self):
        self.assertEqual(bank_workflow.text_currency("Konto EUR, Betrag 12,00 EUR"), "EUR")
        self.assertIsNone(bank_workflow.text_currency("EUR / CHF Umtausch"))
        self.assertIsNone(bank_workflow.text_currency("kein Währungscode"))

    def test_wise_zip_needs_no_column_currency_or_date_prompts(self):
        with tempfile.TemporaryDirectory() as folder:
            statement = Path(folder) / "statement-file.pdf"
            columns = ("TransferWise ID", "Date", "Amount", "Currency", "Description", "Exchange To Amount")
            contents = io.StringIO()
            writer = csv.DictWriter(contents, fieldnames=columns)
            writer.writeheader()
            writer.writerow(dict(zip(columns, ("A", "14-10-2026", "-12.50", "EUR", "Bakery", ""))))
            writer.writerow(dict(zip(columns, ("B", "05-11-2026", "8.00", "EUR", "Refund", ""))))
            with zipfile.ZipFile(statement, "w") as archive:
                archive.writestr("wise.csv", contents.getvalue())
            with patch("builtins.input", side_effect=AssertionError("no prompt expected")), contextlib.redirect_stdout(io.StringIO()):
                rows = bank_import.read_bank_rows(statement, lambda source, currency: "assets:bank:wise")
            self.assertEqual([(r[0], r[2], r[3], r[4]) for r in rows], [
                (date(2026, 10, 14), Decimal("-12.50"), "EUR", "assets:bank:wise"),
                (date(2026, 11, 5), Decimal("8.00"), "EUR", "assets:bank:wise")])

    def test_counter_account_only_when_history_is_consistent(self):
        rows = []
        for index, desc, counter in (
            (1, "Bakery", "expenses:food"), (2, "City Taxi 123", "expenses:transport"),
            (3, "City Taxi 456", "expenses:transport"), (4, "Ambiguous", "expenses:food"),
            (5, "Ambiguous", "expenses:travel"), (6, "Bakery", "expenses:food")):
            rows += [posting(index, desc, "assets:bank:wise", "-10"),
                     posting(index, desc, counter, "10")]
        rows += [posting(7, "Bakery", "assets:bank:other", "-10"),
                 posting(7, "Bakery", "expenses:other", "10")]
        rows += [posting(8, "Exchange", "assets:bank:wise", "-10"),
                 posting(8, "Exchange", "assets:bank:other", "12", "CHF")]
        result = type("Result", (), {"returncode": 0, "stdout": history_csv(rows), "stderr": ""})()
        with patch.object(bank_suggest.bank_import, "hledger_binary", return_value="hledger"), \
             patch.object(bank_suggest.subprocess, "run", return_value=result):
            model = bank_suggest.CounterAccounts("synthetic.journal")
        self.assertEqual(model.suggest("assets:bank:wise", "EUR", "Bakery", Decimal("-10")), "expenses:food")
        self.assertEqual(model.suggest("assets:bank:wise", "EUR", "City Taxi 789", Decimal("-5")), "expenses:transport")
        self.assertIsNone(model.suggest("assets:bank:wise", "EUR", "Bakery", Decimal("10")))
        self.assertIsNone(model.suggest("assets:bank:wise", "EUR", "Ambiguous", Decimal("-10")))
        self.assertIsNone(model.suggest("assets:bank:wise", "CHF", "Bakery", Decimal("-10")))
        self.assertIsNone(model.suggest("assets:bank:wise", "EUR", "Exchange", Decimal("-10")))

    def test_prepare_only_skips_exact_booked_rows_and_keeps_collisions_open(self):
        with tempfile.TemporaryDirectory() as folder:
            journal = Path(folder) / "ledger"
            journal.write_text("synthetic journal")
            rows = [bank_workflow.make_row("2026-10-01", desc, Decimal("-10"), "EUR", "assets:bank:wise", "wise.csv")
                    for desc in ("Already booked", "Already booked", "Wrong description", "Bakery", "New shop")]
            model = type("Model", (), {"suggest": lambda self, bank, currency, desc, amount:
                          "expenses:food" if desc == "Bakery" else None})()
            booked = [(date(2026, 10, 1), Decimal("-10"), "Already booked"),
                      (date(2026, 10, 1), Decimal("-10"), "Other description")]
            # The same amount/date has multiple candidates, so none can be silently skipped.
            with patch.object(bank_workflow.bank_suggest, "CounterAccounts", return_value=model), \
                 patch.object(bank_workflow.bank_import, "ledger_rows", return_value=booked):
                bank_workflow.fill_suggestions(rows, journal)
            self.assertEqual([row["action"] for row in rows], ["?", "?", "?", "?", "?"])
            with patch.object(bank_workflow.bank_suggest, "CounterAccounts", return_value=model), \
                 patch.object(bank_workflow.bank_import, "ledger_rows", return_value=[]):
                bank_workflow.fill_suggestions(rows, journal)
            self.assertEqual(rows[3]["action"], "add")
            self.assertEqual(rows[3]["counter_account"], "expenses:food")
            self.assertEqual(rows[4]["action"], "?")
            unique = [bank_workflow.make_row("2026-10-01", "Already booked", Decimal("-10"), "EUR", "assets:bank:wise", "wise.csv")
                      for _ in range(2)]
            with patch.object(bank_workflow.bank_suggest, "CounterAccounts", return_value=model), \
                 patch.object(bank_workflow.bank_import, "ledger_rows", return_value=booked[:1]):
                bank_workflow.fill_suggestions(unique, journal)
            self.assertEqual([row["action"] for row in unique], ["skip", "?"])


if __name__ == "__main__":
    unittest.main()
