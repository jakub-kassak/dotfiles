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
import re
import shutil
import subprocess
import sys
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


def account(message):
    while True:
        value = prompt(message)
        if value and not re.search(r"[\n\r;\t]", value) and not value.startswith(" "):
            return value
        print("Ungültiger Kontoname.")


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


def read_bank_rows(path):
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
        date_col = column(headers, "Buchungsdatum")
        desc_col = column(headers, "Beschreibung")
        amount_col = column(headers, "signierter Betrag (+ Eingang, - Ausgang)", optional=True)
        if amount_col is None:
            debit_col = column(headers, "Ausgang/Belastung")
            credit_col = column(headers, "Eingang/Gutschrift")
        currency_col = column(headers, "Währung", optional=True)
        id_col = column(headers, "eindeutige Transaktions-ID", optional=True)
        bank = account("hledger-Bankkonto (exakter Name im Ledger)")
        currency = prompt("Währung, falls CSV-Feld leer/fehlt (z.B. CHF)", "CHF").upper()
        date_format = prompt("Datumsformat (Python strptime)", "%Y-%m-%d")
        if not re.fullmatch(r"[A-Z]{3}", currency):
            raise ValueError("Bitte einen dreibuchstabigen Währungscode verwenden")

        for line, row in enumerate(reader, 2):
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
                identifier = row[id_col].strip() if id_col is not None else ""
            except (IndexError, ValueError) as exc:
                raise ValueError(f"{name}, CSV-Zeile {line}: {exc}") from exc
            transactions.append((date, description, amount, curr, bank, identifier))
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
