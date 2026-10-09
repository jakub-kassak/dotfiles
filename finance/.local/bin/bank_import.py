#!/usr/bin/env python3
"""Review bank CSVs against an hledger journal on the same computer.

No files are uploaded. By default, nothing is written. Needs Python 3 and
hledger on the computer holding the authoritative journal. ZIP files may
contain multiple CSVs even if the ZIP was incorrectly named *.pdf.
"""

import argparse
import csv
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from collections import defaultdict
from datetime import datetime
from decimal import Decimal, InvalidOperation
from pathlib import Path


def hledger_binary():
    binary = shutil.which("hledger")
    if binary:
        return binary
    homebrew_binary = Path("/opt/homebrew/bin/hledger")
    if homebrew_binary.is_file():
        return str(homebrew_binary)
    raise ValueError("hledger ist auf diesem Computer nicht installiert")


def prompt(message, default=None):
    suffix = f" [{default}]" if default is not None else ""
    value = input(f"{message}{suffix}: ").strip()
    return value or default or ""


def column(headers, name, optional=False):
    while True:
        answer = prompt(f"Spalte für {name} (Nummer{' / leer = keine' if optional else ''})")
        if optional and not answer:
            return None
        if answer.isdigit() and 1 <= int(answer) <= len(headers):
            return int(answer) - 1
        print("Bitte eine angezeigte Spaltennummer wählen.")


def named_column(headers, aliases):
    def normalize(value):
        return re.sub(r"[\s_-]+", " ", value.strip().casefold())
    normalized = [normalize(header) for header in headers]
    for alias in aliases:
        matches = [index for index, header in enumerate(normalized) if header == alias]
        if len(matches) == 1:
            return matches[0]
    return None


def csv_date_format(values, source, headers):
    values = [value.strip() for value in values if value.strip()]
    if not values:
        return prompt("Datumsformat (Python strptime)", "%Y-%m-%d")
    formats = ("%Y-%m-%d", "%Y/%m/%d", "%d.%m.%Y", "%m.%d.%Y",
               "%d/%m/%Y", "%m/%d/%Y", "%d-%m-%Y", "%m-%d-%Y")
    compatible = []
    for fmt in formats:
        try:
            for value in values:
                datetime.strptime(value, fmt)
            compatible.append(fmt)
        except ValueError:
            pass
    if len(compatible) == 1:
        return compatible[0]
    if set(compatible) == {"%d-%m-%Y", "%m-%d-%Y"} and (
            "wise" in source.casefold() or named_column(headers, ("transferwise id",)) is not None):
        return "%d-%m-%Y"
    return prompt("Datumsformat (Python strptime)", compatible[0] if compatible else "%Y-%m-%d")


def account(message):
    while True:
        value = prompt(message)
        if value and not re.search(r"[\n\r;\t]", value) and not value.startswith(" "):
            return value
        print("Ungültiger Kontoname.")


class AccountResolver:
    """Find a bank posting account locally; remember ambiguous choices privately."""

    def __init__(self, journal, mapping_file):
        self.journal = Path(journal).expanduser()
        self.mapping_file = Path(mapping_file).expanduser()
        self.accounts = set()
        if self.journal.is_file():
            try:
                result = subprocess.run([hledger_binary(), "-f", str(self.journal), "accounts"],
                                        text=True, capture_output=True, check=False)
                if result.returncode:
                    raise ValueError(result.stderr.strip())
                self.accounts = {line.strip() for line in result.stdout.splitlines() if line.strip()}
            except ValueError as exc:
                print(f"Automatische Kontosuche nicht verfügbar: {exc}")
        if self.mapping_file.is_symlink():
            raise ValueError("Kontozuordnung darf kein Symlink sein")
        self.mapping = {}
        self._announced = set()
        if self.mapping_file.is_file():
            try:
                data = json.loads(self.mapping_file.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError) as exc:
                raise ValueError("Lokale Kontozuordnung ist nicht lesbar") from exc
            if data.get("ledger") == str(self.journal.resolve()) and isinstance(data.get("accounts"), dict):
                self.mapping = data["accounts"]

    @staticmethod
    def bank_name(source):
        source = source.lower()
        if "tatra" in source:
            return "tatra"
        if "raiffeisen" in source:
            return "raiffeisen"
        if "wise" in source or source.startswith("statement-file"):
            return "wise"
        return source

    @staticmethod
    def source_identity(source, bank):
        if bank == "tatra":
            # The trailing date changes between statements; the preceding
            # identifier distinguishes different Tatra accounts.
            match = re.fullmatch(r"tatra-(.+)_\d{4}-\d{2}-\d{2}\.pdf", source.lower())
            if match:
                source = match.group(1)
        return hashlib.sha256(source.lower().encode("utf-8")).hexdigest()[:16]

    def _save(self):
        self.mapping_file.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        fd, temporary = tempfile.mkstemp(prefix=".account-map-", dir=self.mapping_file.parent)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                json.dump({"ledger": str(self.journal.resolve()), "accounts": self.mapping}, handle, indent=2)
                handle.write("\n")
            os.chmod(temporary, 0o600)
            os.replace(temporary, self.mapping_file)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)

    def __call__(self, source, currency):
        bank = self.bank_name(source)
        currency = currency.upper()
        candidates = sorted(name for name in self.accounts
                            if bank.casefold() in name.casefold() and
                            name.split(":", 1)[0].casefold() in ("assets", "liabilities"))
        # Never pick a CHF-specific account for an EUR statement, or vice versa.
        known = {"EUR", "CHF", "USD", "GBP", "CZK", "PLN", "HUF", "JPY", "CAD", "AUD", "SEK", "NOK", "DKK"}
        def currency_tokens(name):
            return set(re.findall(r"(?<![A-Z])[A-Z]{3}(?![A-Z])", name.upper())) & known
        candidates = [name for name in candidates if not currency_tokens(name) or currency in currency_tokens(name)]
        exact_currency = [name for name in candidates if currency in currency_tokens(name)]
        options = exact_currency if exact_currency else candidates
        # A unique bank account is safe to reuse; ambiguous accounts are
        # remembered only for this source account/statement identifier.
        key = f"{bank}|{currency}"
        if len(options) != 1:
            key += "|" + self.source_identity(source, bank)
        saved = self.mapping.get(key)
        if isinstance(saved, str) and (not self.accounts or saved in self.accounts):
            if key not in self._announced:
                print(f"Bankkonto (lokal gemerkt): {saved}")
                self._announced.add(key)
            return saved
        if len(options) == 1:
            selected = options[0]
            print(f"Bankkonto eindeutig zugeordnet: {selected}")
        else:
            if options:
                print(f"Mögliche hledger-Konten für {bank} ({currency}):")
                for index, name in enumerate(options, 1):
                    print(f"  {index}: {name}")
            while True:
                answer = prompt(f"Bankkonto für {bank} ({currency}): Nummer oder exakter Name")
                if answer.isdigit() and 1 <= int(answer) <= len(options):
                    selected = options[int(answer) - 1]
                    break
                if answer and not re.search(r"[\n\r;\t]", answer) and (not self.accounts or answer in self.accounts):
                    selected = answer
                    break
                print("Bitte ein vorhandenes hledger-Konto eingeben.")
        self.mapping[key] = selected
        self._save()
        self._announced.add(key)
        return selected


def parse_number(value):
    text = value.strip().replace("\u00a0", "").replace("\u202f", "")
    text = text.replace(" ", "").replace("'", "").replace("−", "-")
    negative = text.startswith("(") and text.endswith(")")
    if negative:
        text = text[1:-1]
    # Both decimal conventions, with optional thousands separators.
    if "," in text and "." in text:
        text = text.replace(".", "") if text.rfind(",") > text.rfind(".") else text.replace(",", "")
    if "," in text:
        text = text.replace(",", ".")
    try:
        result = Decimal(text)
    except InvalidOperation as exc:
        raise ValueError(f"Betrag nicht lesbar: {value!r}") from exc
    if not result.is_finite():
        raise ValueError("Betrag ist nicht endlich")
    return -result if negative else result


def parse_date(value, date_format):
    return datetime.strptime(value.strip(), date_format).date()


def decode_csv(data):
    for encoding in ("utf-8-sig", "utf-16", "cp1250"):
        try:
            text = data.decode(encoding)
            if "\x00" not in text:
                return text
        except UnicodeDecodeError:
            pass
    raise ValueError("CSV-Zeichensatz unbekannt (UTF-8, UTF-16 und CP1250 versucht)")


def input_csvs(path):
    if zipfile.is_zipfile(path):
        with zipfile.ZipFile(path) as archive:
            names = [n for n in archive.namelist() if n.lower().endswith(".csv") and not n.startswith("__MACOSX/")]
            if not names:
                raise ValueError("ZIP enthält keine CSV-Dateien")
            for name in names:
                if archive.getinfo(name).file_size > 20_000_000:
                    raise ValueError("CSV im ZIP ist über 20 MB")
                yield name, archive.read(name)
    elif path.suffix.lower() == ".csv":
        yield path.name, path.read_bytes()
    else:
        raise ValueError("Nur CSV oder ZIP mit CSV-Dateien unterstützt (auch fehlbenanntes .pdf-ZIP)")


def read_bank_rows(path, account_resolver=None):
    transactions = []
    for name, data in input_csvs(path):
        text = decode_csv(data)
        try:
            dialect = csv.Sniffer().sniff(text[:8192], delimiters=",;\t")
            reader = csv.reader(io.StringIO(text), dialect)
        except csv.Error:
            reader = csv.reader(io.StringIO(text))
        headers = next(reader, None)
        if not headers:
            raise ValueError(f"{name}: keine Spaltenüberschrift")
        print(f"\n{name} – Spalten:")
        for index, header in enumerate(headers, 1):
            print(f"  {index}: {header}")
        rows = list(reader)
        date_col = named_column(headers, ("date", "booking date", "buchungsdatum", "datum"))
        if date_col is None:
            date_col = column(headers, "Buchungsdatum")
        desc_col = named_column(headers, ("description", "beschreibung", "text", "details"))
        if desc_col is None:
            desc_col = column(headers, "Beschreibung")
        amount_col = named_column(headers, ("amount", "betrag", "signed amount", "betrag (signiert)"))
        if amount_col is None:
            amount_col = column(headers, "signierter Betrag (+ Eingang, - Ausgang)", optional=True)
        if amount_col is None:
            debit_col = named_column(headers, ("debit", "belastung", "ausgang"))
            credit_col = named_column(headers, ("credit", "gutschrift", "eingang"))
            if debit_col is None:
                debit_col = column(headers, "Ausgang/Belastung")
            if credit_col is None:
                credit_col = column(headers, "Eingang/Gutschrift")
        currency_col = named_column(headers, ("currency", "währung", "waehrung"))
        if currency_col is None:
            currency_col = column(headers, "Währung", optional=True)
        id_col = named_column(headers, ("transferwise id", "transaction id", "transaction reference", "transaktions id"))
        if id_col is None:
            id_col = column(headers, "eindeutige Transaktions-ID", optional=True)
        bank = account("hledger-Bankkonto (exakter Name im Ledger)") if account_resolver is None else None
        needs_currency = currency_col is None or any(
            len(row) <= currency_col or not row[currency_col].strip()
            for row in rows if any(cell.strip() for cell in row))
        currency = (prompt("Währung, falls CSV-Feld leer/fehlt (z.B. CHF)", "CHF").upper()
                    if needs_currency else "")
        date_format = csv_date_format(
            [row[date_col] for row in rows if len(row) > date_col][:30], name, headers)
        if currency and not re.fullmatch(r"[A-Z]{3}", currency):
            raise ValueError("Bitte einen dreibuchstabigen Währungscode verwenden")

        print(f"Verwendete Spalten: Datum {date_col + 1}, Text {desc_col + 1}, "
              f"Betrag {amount_col + 1 if amount_col is not None else 'Belastung/Gutschrift'}, "
              f"Währung {currency_col + 1 if currency_col is not None else currency}; Datum {date_format}")
        for line, row in enumerate(rows, 2):
            if not any(cell.strip() for cell in row):
                continue
            try:
                date = parse_date(row[date_col], date_format)
                description = " ".join(row[desc_col].split()).replace(";", ",")
                if not description:
                    raise ValueError("Beschreibung fehlt")
                if amount_col is not None:
                    amount = parse_number(row[amount_col])
                else:
                    debit = parse_number(row[debit_col]) if row[debit_col].strip() else Decimal(0)
                    credit = parse_number(row[credit_col]) if row[credit_col].strip() else Decimal(0)
                    if debit and credit:
                        raise ValueError("Eingang und Ausgang zugleich belegt")
                    amount = abs(credit) - abs(debit)
                if not amount:
                    raise ValueError("Betrag ist null oder fehlt")
                curr = (row[currency_col].strip() if currency_col is not None else "") or currency
                curr = curr.upper()
                if not re.fullmatch(r"[A-Z]{3}", curr):
                    raise ValueError(f"Unbekannte Währung: {curr!r}")
                row_bank = account_resolver(path.name, curr) if account_resolver else bank
                identifier = row[id_col].strip() if id_col is not None else ""
            except (IndexError, ValueError) as exc:
                raise ValueError(f"{name}, CSV-Zeile {line}: {exc}") from exc
            transactions.append((date, description, amount, curr, row_bank, identifier))
    return transactions


def parse_hledger_amount(value, expected_currency):
    """Accept simple hledger CSV register amounts (eg 'CHF-12.50', '-12.50 CHF')."""
    value = value.strip().replace("\u00a0", " ")
    currency = re.escape(expected_currency)
    number = r"[+-]?(?:\d+(?:[.,]\d+)?)"
    patterns = (rf"^{currency}\s*({number})$", rf"^({number})\s*{currency}$")
    for pattern in patterns:
        found = re.fullmatch(pattern, value)
        if found:
            return parse_number(found.group(1))
    raise ValueError(f"hledger-Betrag {value!r} nicht als {expected_currency} lesbar")


def ledger_rows(journal, bank, currency):
    # hledger reads includes/aliases and inferred posting amounts itself.
    command = [hledger_binary(), "-f", str(journal), "register", "-O", "csv",
               "acct:^" + re.escape(bank) + "$", "cur:^" + currency + "$"]
    result = subprocess.run(command, text=True, capture_output=True, check=False)
    if result.returncode:
        raise ValueError(f"hledger konnte das Ledger nicht auswerten: {result.stderr.strip()}")
    if not result.stdout.strip():
        return []  # This account has no postings yet.
    reader = csv.DictReader(io.StringIO(result.stdout))
    if not reader.fieldnames or not {"date", "account", "amount"} <= set(reader.fieldnames):
        raise ValueError("Unbekanntes hledger-register-CSV-Format; Import abgebrochen")
    records = []
    for row in reader:
        if row["account"] != bank:
            continue
        raw = row["amount"].strip()
        if not raw:
            raise ValueError("Leerer hledger-Bankbetrag; Import abgebrochen")
        records.append((parse_date(row["date"], "%Y-%m-%d"),
                        parse_hledger_amount(raw, currency), row.get("description", "")))
    return records


def candidates(tx, booked, tolerance_days):
    date, _, amount, _, _, _ = tx
    return [(i, rec) for i, rec in enumerate(booked)
            if rec[1] == amount and abs((rec[0] - date).days) <= tolerance_days]


def verify_bank_accounts(journal, banks):
    result = subprocess.run([hledger_binary(), "-f", str(journal), "accounts"],
                            text=True, capture_output=True, check=False)
    if result.returncode:
        raise ValueError(f"hledger konnte die Konten nicht prüfen: {result.stderr.strip()}")
    existing = {line.strip() for line in result.stdout.splitlines()}
    missing = banks - existing
    if missing:
        raise ValueError("Bankkonto nicht im Ledger vorhanden: " + ", ".join(sorted(missing)))


def format_entry(tx):
    date, description, amount, currency, bank, _ = tx
    opposite = "expenses:unknown" if amount < 0 else "income:unknown"
    return (f"{date.isoformat()} {description}\n"
            f"    {bank}  {amount} {currency}\n"
            f"    {opposite}  {-amount} {currency}\n\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("statement", type=Path, help="CSV oder ZIP (auch als .pdf benannt)")
    parser.add_argument("ledger", type=Path, help="Maßgebliche hledger-Journaldatei auf diesem Laptop")
    parser.add_argument("--days", type=int, default=2, help="Maximaler Datumsabstand für Duplikatverdacht (Standard: 2)")
    parser.add_argument("--apply", action="store_true", help="Nach Einzelprüfung direkt an das Ledger anhängen")
    args = parser.parse_args()
    if args.days < 0 or not args.statement.is_file() or not args.ledger.is_file():
        parser.error("--days >= 0 und beide Dateien müssen lokal existieren")
    try:
        transactions = read_bank_rows(args.statement)
        if not transactions:
            print("Keine Transaktionen gefunden.")
            return 0
        verify_bank_accounts(args.ledger, {tx[4] for tx in transactions})
        booked_by_account = {}
        for bank, currency in {(tx[4], tx[3]) for tx in transactions}:
            booked_by_account[bank, currency] = ledger_rows(args.ledger, bank, currency)
        selected = []
        # Reserve each existing posting at most once when deciding; an exact
        # amount/date collision may still be a different real transaction.
        used = defaultdict(set)
        for tx in transactions:
            date, description, amount, currency, bank, identifier = tx
            key = bank, currency
            matches = candidates(tx, booked_by_account[key], args.days)
            available = [(idx, rec) for idx, rec in matches if idx not in used[key]]
            print(f"\n{date} | {amount} {currency} | {bank} | {description}")
            if identifier:
                print(f"  Bank-Referenz: {identifier}")
            for idx, (other_date, _, other_desc) in matches[:10]:
                state = "bereits zugeordnet" if idx in used[key] else "möglicher Treffer"
                print(f"  {state}: {other_date} | {other_desc}")
            if len(matches) > 10:
                print(f"  ... {len(matches) - 10} weitere mögliche Treffer")
            if matches:
                # Never silently classify a collision as new. Multiple equal
                # transactions need an explicit human decision.
                decision = prompt("[s]kip / [a]ufnehmen / [q]uit", "s").lower()
            else:
                decision = prompt("[a]ufnehmen / [s]kip / [q]uit", "a").lower()
            if decision == "q":
                print("Abgebrochen; nichts geschrieben.")
                return 0
            if decision not in ("a", "s"):
                raise ValueError("Ungültige Auswahl; nichts geschrieben")
            if decision == "s":
                if available:
                    used[key].add(available[0][0])
            else:
                selected.append(tx)
                # Avoid proposing another identical CSV entry without warning.
                booked_by_account[key].append((date, amount, description))
                used[key].add(len(booked_by_account[key]) - 1)

        print(f"\n{len(selected)} Buchungen ausgewählt.")
        if not selected:
            return 0
        print("\nVorschau:\n")
        for tx in selected:
            print(format_entry(tx), end="")
        if not args.apply:
            print("Testlauf: nichts geschrieben. Für tatsächliches Anhängen --apply angeben.")
            return 0
        if prompt("Alle Buchungen ans Ledger anhängen? Tippe JA") != "JA":
            print("Abgebrochen; nichts geschrieben.")
            return 0
        check = subprocess.run([hledger_binary(), "-f", str(args.ledger), "check"],
                               text=True, capture_output=True, check=False)
        if check.returncode:
            raise ValueError(f"Ledger-Prüfung fehlgeschlagen, nichts geschrieben: {check.stderr.strip()}")
        with args.ledger.open("a", encoding="utf-8") as journal:
            journal.write("\n" + "".join(format_entry(tx) for tx in selected))
        print(f"{len(selected)} Buchungen angehängt. Bitte 'hledger -f LEDGER check' ausführen und Geräte synchronisieren.")
        return 0
    except (OSError, ValueError, zipfile.BadZipFile, FileNotFoundError) as exc:
        print(f"Fehler: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
