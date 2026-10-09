"""Conservative counter-account suggestions from the local hledger journal."""

import csv
import io
import re
import subprocess
from collections import defaultdict

import bank_import


def normalized(text):
    return " ".join(text.casefold().split())


def without_numbers(text):
    return " ".join(re.sub(r"\b\d+(?:[.,]\d+)*\b", " ", normalized(text)).split())


class CounterAccounts:
    def __init__(self, journal):
        result = subprocess.run([bank_import.hledger_binary(), "-f", str(journal), "print", "-O", "csv"],
                                text=True, capture_output=True, check=False)
        if result.returncode:
            raise ValueError(f"hledger konnte bisherige Buchungen nicht lesen: {result.stderr.strip()}")
        reader = csv.DictReader(io.StringIO(result.stdout))
        if not reader.fieldnames or not {"txnidx", "description", "account", "amount", "commodity"} <= set(reader.fieldnames):
            raise ValueError("Unbekanntes hledger-print-CSV-Format; keine Kontovorschläge möglich")
        self.exact = defaultdict(set)
        self.patterns = defaultdict(list)
        transactions = defaultdict(list)
        for row in reader:
            transactions[row["txnidx"]].append(row)
        for postings in transactions.values():
            if len(postings) != 2:
                continue
            for bank_row, counter_row in (postings, postings[::-1]):
                bank, counter = bank_row["account"], counter_row["account"]
                currency = bank_row["commodity"]
                if (bank == counter or not currency or currency != counter_row["commodity"]
                        or not bank_row["amount"] or not counter_row["amount"]
                        or counter in ("expenses:unknown", "income:unknown")):
                    continue
                amount = bank_import.parse_number(bank_row["amount"])
                if amount != -bank_import.parse_number(counter_row["amount"]):
                    continue
                description = normalized(bank_row["description"])
                if not description:
                    continue
                direction = amount > 0
                self.exact[bank, currency, direction, description].add(counter)
                pattern = without_numbers(description)
                if len(pattern) >= 8 and pattern not in ("card payment", "bank transfer", "payment", "transfer"):
                    self.patterns[bank, currency, direction, pattern].append(counter)

    def suggest(self, bank, currency, description, amount):
        exact = self.exact.get((bank, currency, amount > 0, normalized(description)), set())
        if len(exact) == 1:
            return next(iter(exact))
        if exact:  # A contradictory exact match must not be overridden by a broader pattern.
            return None
        patterns = self.patterns.get((bank, currency, amount > 0, without_numbers(description)), [])
        if len(patterns) >= 2 and len(set(patterns)) == 1:
            return patterns[0]
        return None
