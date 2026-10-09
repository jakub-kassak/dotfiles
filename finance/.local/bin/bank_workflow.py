#!/usr/bin/env python3
"""Local, interactive ZIP/CSV + PDF + screenshot -> editable TSV -> hledger workflow.

prepare runs without access to the ledger. check/apply must run where the
authoritative hledger journal lives. Screenshots are processed by local
Tesseract; this script has no network functionality.
"""

import argparse
import csv
import getpass
import hashlib
import io
import os
import re
import subprocess
import sys
import zipfile
from datetime import date, datetime
from decimal import Decimal
from pathlib import Path

import bank_import


WORK_DIR = Path.home() / "Library/Application Support/BankWorkflow"
FIELDS = ("action", "date", "description", "amount", "currency",
          "bank_account", "counter_account", "source", "counter_amount", "counter_currency")
OLD_FIELDS = FIELDS[:-2]
DATE_PATTERN = re.compile(r"\b(?:\d{4}[-./]\d{1,2}[-./]\d{1,2}|\d{1,2}[-./]\d{1,2}[-./]\d{4})\b")
AMOUNT_PATTERN = re.compile(r"(?<!\w)[+-]?(?:\d{1,3}(?:[ '\u00a0.,]\d{3})+|\d+)(?:[.,]\d{2})(?!\w)")
PDF_ROW = re.compile(r"^(\d{2}\.\d{2}\.\d{4})\s")
PDF_VALUE_DATE = re.compile(r"\s+\d{2}\.\d{2}\.\d{4}\s*$")
IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg", ".tif", ".tiff", ".bmp", ".webp"}


def date_guess(text):
    guesses = []
    for value in DATE_PATTERN.findall(text):
        for fmt in ("%Y-%m-%d", "%Y/%m/%d", "%d.%m.%Y", "%d/%m/%Y", "%d-%m-%Y", "%Y.%m.%d"):
            try:
                result = datetime.strptime(value, fmt).date().isoformat()
                if result not in guesses:
                    guesses.append(result)
                break
            except ValueError:
                pass
    return guesses


def text_line(lines, label, default=""):
    while True:
        answer = bank_import.prompt(f"{label}: OCR-Zeilennummer oder Text", default)
        if answer.isdigit() and 1 <= int(answer) <= len(lines):
            return lines[int(answer) - 1]
        if answer:
            return answer
        print("Bitte eine Zeile oder Text eingeben.")


def image_rows(image, language, account_resolver=None):
    result = subprocess.run(["tesseract", str(image), "stdout", "-l", language],
                            text=True, capture_output=True, check=False)
    if result.returncode:
        raise ValueError(f"OCR fehlgeschlagen: {result.stderr.strip()}")
    return interactive_text_rows(result.stdout, image.name, "OCR", account_resolver)


def interactive_text_rows(text, source, kind, account_resolver=None):
    lines = [" ".join(line.split()) for line in text.splitlines() if line.strip()]
    print(f"\n{kind} aus {source} (lokal auf deinem Rechner):")
    for index, line in enumerate(lines, 1):
        print(f"  {index:>3}: {line}")
    if not lines:
        print("Kein Text erkannt; Screenshot übersprungen.")
        return []
    guesses = date_guess(text)
    print("Mögliche Daten:", ", ".join(guesses) or "keine")
    # A date like 10.10.2026 must not appear as an amount candidate.
    amounts = list(dict.fromkeys(AMOUNT_PATTERN.findall(DATE_PATTERN.sub(" ", text))))
    print("Mögliche Beträge:")
    for index, value in enumerate(amounts, 1):
        print(f"  {index}: {value}")
    if not amounts:
        print("  keine")
    currency = bank_import.prompt("Währung (z.B. EUR/CHF)").upper()
    if not re.fullmatch(r"[A-Z]{3}", currency):
        raise ValueError("Währung muss aus drei Buchstaben bestehen")
    bank = (account_resolver(source, currency) if account_resolver else
            bank_import.account("hledger-Bankkonto für diesen Screenshot"))
    result_rows = []
    while True:
        print("\nTransaktion aus diesem Screenshot erfassen (q zum Überspringen/Beenden).")
        raw_date = bank_import.prompt("Datum YYYY-MM-DD oder q", guesses[0] if len(guesses) == 1 else None)
        if not raw_date or raw_date.lower() == "q":
            break
        try:
            date.fromisoformat(raw_date)
        except ValueError as exc:
            raise ValueError(f"Datum muss YYYY-MM-DD sein: {raw_date}") from exc
        description = text_line(lines, "Händler/Beschreibung").replace("\t", " ")
        while True:
            raw_amount = bank_import.prompt("Betrag: OCR-Betragsnummer oder Zahl (z.B. 12,50)")
            numbers = ([amounts[int(raw_amount) - 1]] if raw_amount.isdigit() and
                       1 <= int(raw_amount) <= len(amounts) else AMOUNT_PATTERN.findall(raw_amount))
            if len(numbers) == 1:
                break
            print("Bitte eine eindeutige OCR-Betragsnummer oder genau eine Zahl angeben.")
        amount = abs(bank_import.parse_number(numbers[0]))
        if amount == 0:
            raise ValueError("Betrag darf nicht null sein")
        direction = bank_import.prompt("Ausgabe [a] oder Einnahme [e]", "a").lower()
        if direction not in ("a", "e"):
            raise ValueError("Richtung muss a oder e sein")
        amount = -amount if direction == "a" else amount
        result_rows.append(make_row(raw_date, description, amount, currency, bank, source))
        if bank_import.prompt("Weitere Transaktion auf diesem Screenshot? [j/N]", "n").lower() != "j":
            break
    return result_rows


def pdf_rows(path, password, account_resolver=None):
    try:
        from pypdf import PdfReader
    except ImportError as exc:
        raise ValueError("Für PDF-Import bitte lokal 'python3 -m pip install pypdf' ausführen") from exc
    with path.open("rb") as handle:
        reader = PdfReader(handle)
        if not reader.is_encrypted:
            return raiffeisen_pdf_rows(path, account_resolver), password
        if password is None:
            password = getpass.getpass("Passwort für verschlüsselte Bank-PDFs: ")
        if not reader.decrypt(password):
            # A second encrypted PDF may use a different password.
            password = getpass.getpass(f"Passwort für {path.name}: ")
            if not reader.decrypt(password):
                raise ValueError(f"PDF-Passwort für {path.name} nicht akzeptiert")
        pages = [page.extract_text(extraction_mode="layout") for page in reader.pages]
    text = "\n".join(page or "" for page in pages)
    if not text.strip():
        raise ValueError("Verschlüsseltes PDF enthält keinen extrahierbaren Text; bitte Screenshot verwenden")
    return interactive_text_rows(text, path.name, "Entschlüsselter PDF-Text", account_resolver), password


def make_row(date_value, description, amount, currency, bank, source):
    return {"action": "?", "date": str(date_value), "description": description,
            "amount": str(amount), "currency": currency, "bank_account": bank,
            "counter_account": "expenses:unknown" if amount < 0 else "income:unknown",
            "source": source, "counter_amount": "", "counter_currency": ""}


def raiffeisen_pdf_rows(path, account_resolver=None):
    result = subprocess.run(["pdftotext", "-layout", str(path), "-"],
                            text=True, capture_output=True, check=False)
    if result.returncode:
        raise ValueError(f"PDF-Text konnte nicht gelesen werden: {result.stderr.strip()}")
    if not result.stdout.strip():
        raise ValueError("PDF hat keinen extrahierbaren Text; für gescannte PDFs bitte Screenshots verwenden")
    columns = None
    entries = []
    for line in result.stdout.splitlines():
        if all(title in line for title in ("Datum", "Text", "Belastung", "Gutschrift", "Valuta")):
            columns = (line.index("Text"), line.index("Belastung"), line.index("Gutschrift"))
            continue
        match = PDF_ROW.match(line)
        if not match or columns is None:
            continue
        text_start, debit_start, credit_start = columns
        if not (text_start < debit_start < credit_start):
            raise ValueError("Unerwartete Raiffeisen-PDF-Spaltenanordnung")
        body = PDF_VALUE_DATE.sub("", line)
        if body == line:
            raise ValueError("Raiffeisen-PDF-Zeile ohne Valutadatum; bitte Format prüfen")
        debit_values = AMOUNT_PATTERN.findall(body[debit_start:credit_start])
        credit_values = AMOUNT_PATTERN.findall(body[credit_start:])
        if len(debit_values) + len(credit_values) != 1:
            raise ValueError("Raiffeisen-PDF-Zeile ohne eindeutige Belastung/Gutschrift")
        description = " ".join(line[text_start:debit_start].split())
        if not description:
            raise ValueError("Raiffeisen-PDF-Zeile ohne Buchungstext")
        amount = (abs(bank_import.parse_number(credit_values[0])) if credit_values
                  else -abs(bank_import.parse_number(debit_values[0])))
        entries.append((datetime.strptime(match.group(1), "%d.%m.%Y").date(), description, amount))
    if not entries:
        raise ValueError("Keine Raiffeisen-Umsätze gefunden; PDF-Layout ist möglicherweise anders")
    print(f"\n{path.name}: {len(entries)} Buchungen anhand Datum/Text/Belastung/Gutschrift extrahiert.")
    currency = bank_import.prompt("Währung des PDF-Kontos (z.B. CHF)").upper()
    if not re.fullmatch(r"[A-Z]{3}", currency):
        raise ValueError("Währung muss drei Großbuchstaben haben")
    bank = (account_resolver(path.name, currency) if account_resolver else
            bank_import.account("hledger-Bankkonto für diesen Raiffeisen-Auszug"))
    return [make_row(day.isoformat(), desc, amount, currency, bank, path.name)
            for day, desc, amount in entries]


def discover_inputs(inbox):
    if not inbox.is_dir():
        raise ValueError(f"Eingangsordner fehlt: {inbox}")
    statements, images = [], []
    for path in sorted(inbox.iterdir()):
        if path.is_symlink() or not path.is_file():
            continue
        if path.suffix.lower() in IMAGE_SUFFIXES:
            images.append(path)
        elif path.suffix.lower() == ".csv":
            statements.append(path)
        else:
            with path.open("rb") as handle:
                is_pdf = handle.read(4) == b"%PDF"
            if is_pdf or zipfile.is_zipfile(path):
                statements.append(path)
            else:
                print(f"Übersprungen (unbekanntes Format): {path.name}")
    if not statements and not images:
        raise ValueError(f"Keine CSV-, ZIP-, PDF- oder Bilddateien in {inbox} gefunden")
    print(f"Gefunden: {len(statements)} Auszüge, {len(images)} Bilder in {inbox}")
    for path in statements + images:
        print("  ", path.name)
    return statements, images


def prepare(args):
    if args.draft.exists():
        raise ValueError(f"Entwurf existiert bereits: {args.draft}. Bitte zuerst sichern oder anderen Namen wählen")
    statements, images = (args.statement, args.image) if args.statement or args.image else discover_inputs(args.inbox)
    account_resolver = bank_import.AccountResolver(args.ledger, args.account_map)
    rows = []
    pdf_password = None  # Reuse during this run only; never persist it.
    for statement in statements:
        if not statement.is_file():
            raise ValueError(f"Auszug existiert nicht: {statement}")
        with statement.open("rb") as handle:
            is_pdf = handle.read(4) == b"%PDF"
        if is_pdf:
            pdf_transactions, pdf_password = pdf_rows(statement, pdf_password, account_resolver)
            rows.extend(pdf_transactions)
        else:
            for day, desc, amount, curr, bank, _ in bank_import.read_bank_rows(statement, account_resolver):
                rows.append(make_row(day.isoformat(), desc, amount, curr, bank, statement.name))
    for image in images:
        if not image.is_file():
            raise ValueError(f"Screenshot existiert nicht: {image}")
        rows.extend(image_rows(image, args.ocr_lang, account_resolver))
    if not rows:
        raise ValueError("Keine Transaktionen erfasst; kein Entwurf erstellt")
    # All parsing and OCR finished before the first write.
    args.draft.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd = os.open(args.draft, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS, delimiter="\t")
        writer.writeheader()
        writer.writerows(rows)
    print(f"\n{len(rows)} Zeilen in {args.draft}. Mit nvim öffnen und 'action' auf add/skip setzen.")
    print("Die Beträge sind aus Sicht des Bankkontos: Ausgabe negativ, Eingang positiv.")
    print("Umbuchung: counter_account auf das andere Bankkonto setzen und die zweite CSV-Zeile skippen.")
    print("Währungswechsel: auch counter_amount und counter_currency ausfüllen (z.B. 105.00 und EUR).")


def load_draft(path):
    with path.open(encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        if reader.fieldnames not in (list(FIELDS), list(OLD_FIELDS)):
            raise ValueError("Entwurf benötigt unveränderte TSV-Spalten: " + ", ".join(FIELDS))
        rows = list(reader)
        if reader.fieldnames == list(OLD_FIELDS):
            for row in rows:
                row["counter_amount"] = ""
                row["counter_currency"] = ""
    if not rows:
        raise ValueError("Entwurf enthält keine Buchungen")
    for index, row in enumerate(rows, 2):
        if None in row or any(v is None for v in row.values()):
            raise ValueError(f"TSV-Zeile {index}: fehlerhafte Spaltenzahl; Tabs innerhalb von Feldern entfernen")
        row["action"] = row["action"].strip().lower()
        if row["action"] not in ("add", "skip", "add!"):
            raise ValueError(f"TSV-Zeile {index}: action muss add, skip oder add! sein")
        try:
            date.fromisoformat(row["date"])
            amount = bank_import.parse_number(row["amount"])
        except ValueError as exc:
            raise ValueError(f"TSV-Zeile {index}: {exc}") from exc
        if amount == 0:
            raise ValueError(f"TSV-Zeile {index}: Betrag ist null")
        if not re.fullmatch(r"[A-Z]{3}", row["currency"]):
            raise ValueError(f"TSV-Zeile {index}: Währung muss drei Großbuchstaben haben")
        if not row["description"].strip() or re.search(r"[\r\n\t]", row["description"]):
            raise ValueError(f"TSV-Zeile {index}: Beschreibung ungültig")
        for field in ("bank_account", "counter_account"):
            if not row[field].strip() or re.search(r"[\r\n\t;]", row[field]):
                raise ValueError(f"TSV-Zeile {index}: {field} ungültig")
        counter_amount = row["counter_amount"].strip()
        counter_currency = row["counter_currency"].strip()
        if bool(counter_amount) != bool(counter_currency):
            raise ValueError(f"TSV-Zeile {index}: counter_amount und counter_currency beide ausfüllen oder leer lassen")
        if counter_amount:
            if not re.fullmatch(r"[A-Z]{3}", counter_currency):
                raise ValueError(f"TSV-Zeile {index}: counter_currency muss drei Großbuchstaben haben")
            other = bank_import.parse_number(counter_amount)
            if other == 0 or (other > 0) == (amount > 0):
                raise ValueError(f"TSV-Zeile {index}: Gegenbetrag braucht umgekehrtes Vorzeichen")
            if counter_currency == row["currency"] and other != -amount:
                raise ValueError(f"TSV-Zeile {index}: gleiche Währung muss exakt ausgleichen")
        if row["bank_account"] == row["counter_account"] and not counter_amount:
            raise ValueError(f"TSV-Zeile {index}: Umbuchung auf dasselbe Konto ohne Währungswechsel")
    return rows


def transaction(row):
    return (date.fromisoformat(row["date"]), row["description"],
            bank_import.parse_number(row["amount"]), row["currency"],
            row["bank_account"], "")


def opposite_amount(row):
    bank_amount = bank_import.parse_number(row["amount"])
    if row["counter_amount"].strip():
        return bank_import.parse_number(row["counter_amount"]), row["counter_currency"]
    return -bank_amount, row["currency"]


def validate(rows, journal, days):
    if days < 0:
        raise ValueError("--days muss >= 0 sein")
    active = [row for row in rows if row["action"] != "skip"]
    bank_import.verify_bank_accounts(journal, {row["bank_account"] for row in active})
    bank_names = {row["bank_account"] for row in rows}
    bank_keys = {(row["bank_account"], row["currency"]) for row in active}
    for row in active:
        counter = row["counter_account"]
        if counter in bank_names or counter.split(":", 1)[0].casefold() in ("assets", "liabilities"):
            _, curr = opposite_amount(row)
            bank_keys.add((counter, curr))
    ledger = {key: bank_import.ledger_rows(journal, *key)
              for key in bank_keys}
    errors = []
    for index, row in enumerate(rows, 2):
        if row["action"] == "skip":
            continue
        tx = transaction(row)
        key = tx[4], tx[3]
        existing = bank_import.candidates(tx, ledger[key], days)
        other = [(j, item) for j, item in enumerate(rows, 2)
                 if j != index and item["action"] != "skip" and
                 item["bank_account"] == tx[4] and item["currency"] == tx[3] and
                 bank_import.parse_number(item["amount"]) == tx[2] and
                 abs((date.fromisoformat(item["date"]) - tx[0]).days) <= days]
        # Both banks may export the two legs of one transfer. Only one draft
        # row should be added once its counter_account names the other bank.
        opposite, opposite_currency = opposite_amount(row)
        target_key = row["counter_account"], opposite_currency
        matching_target = (bank_import.candidates(
            (tx[0], tx[1], opposite, opposite_currency, row["counter_account"], ""),
            ledger[target_key], days) if target_key in ledger else [])
        transfer_legs = [(j, item) for j, item in enumerate(rows, 2)
                         if j != index and item["action"] != "skip" and
                         item["bank_account"] == row["counter_account"] and
                         item["currency"] == opposite_currency and
                         bank_import.parse_number(item["amount"]) == opposite and
                         abs((date.fromisoformat(item["date"]) - tx[0]).days) <= days]
        if existing or other or transfer_legs or matching_target:
            print(f"Zeile {index}: DUPLIKATVERDACHT {tx[0]} {tx[2]} {tx[3]} {tx[1]}")
            for _, (day, _, description) in existing[:10]:
                print(f"  Im Ledger: {day} {description}")
            if other:
                print("  Weitere Entwurfszeilen:", ", ".join(str(j) for j, _ in other))
            if transfer_legs:
                print("  Mögliche zweite Umbuchungsseite:", ", ".join(str(j) for j, _ in transfer_legs))
            for _, (day, _, description) in matching_target[:10]:
                print(f"  Mögliche zweite Umbuchungsseite im Ledger: {day} {description}")
            if row["action"] != "add!":
                errors.append(f"Zeile {index}: bei Verdacht 'skip' oder nach Prüfung 'add!' setzen")
    if errors:
        raise ValueError("\n".join(errors))
    return active


def checked_path(draft):
    return draft.with_name(draft.name + ".checked.sha256")


def applied_path(draft):
    return draft.with_name(draft.name + ".applied.sha256")


def check_ledger(journal):
    result = subprocess.run([bank_import.hledger_binary(), "-f", str(journal), "check"],
                            text=True, capture_output=True, check=False)
    if result.returncode:
        raise ValueError(f"hledger check fehlgeschlagen: {result.stderr.strip()}")


def render(row):
    day, description, amount, currency, bank, _ = transaction(row)
    description = " ".join(description.split()).replace(";", ",")
    opposite, other_currency = opposite_amount(row)
    bank_posting = f"    {bank}  {amount} {currency}"
    other_posting = f"    {row['counter_account']}  {opposite} {other_currency}"
    if currency != other_currency:
        # Price the negative leg in the positive leg's currency, so hledger
        # checks both recorded amounts instead of silently inferring a rate.
        if amount < 0:
            bank_posting += f" @@ {opposite} {other_currency}"
        else:
            other_posting += f" @@ {amount} {currency}"
    return f"{day.isoformat()} {description}\n{bank_posting}\n{other_posting}\n\n"


def verify(args, apply=False):
    rows = load_draft(args.draft)
    # Even for apply, re-evaluate against the *current* entire hledger journal.
    active = validate(rows, args.ledger, args.days)
    check_ledger(args.ledger)
    digest = hashlib.sha256(args.draft.read_bytes()).hexdigest()
    print(f"Prüfung erfolgreich: {len(active)} hinzufügen, {len(rows) - len(active)} überspringen.")
    if not apply:
        checked_path(args.draft).write_text(digest + "\n", encoding="ascii")
        print(f"Prüfvermerk: {checked_path(args.draft)}. Nun ggf. --apply ausführen.")
        return
    if not checked_path(args.draft).exists() or checked_path(args.draft).read_text(encoding="ascii").strip() != digest:
        raise ValueError("Entwurf seit der letzten Prüfung geändert oder nicht geprüft; zuerst 'check' ausführen")
    if not active:
        applied_path(args.draft).write_text(digest + "\n", encoding="ascii")
        checked_path(args.draft).unlink()
        print("Nichts hinzuzufügen. Der Entwurf kann nun mit 'cleanup' aufgeräumt werden.")
        return
    print("\nVorschau der endgültigen hledger-Buchungen:")
    for row in active:
        print(render(row), end="")
    if bank_import.prompt("Ans maßgebliche Ledger anhängen? Tippe JA") != "JA":
        print("Abgebrochen; keine Änderung.")
        return
    # If the post-write check fails, undo only our append. A prior backup or
    # version-control snapshot is still recommended before importing.
    original_size = args.ledger.stat().st_size
    try:
        with args.ledger.open("a", encoding="utf-8") as handle:
            handle.write("\n" + "".join(render(row) for row in active))
        check_ledger(args.ledger)
        applied_path(args.draft).write_text(digest + "\n", encoding="ascii")
    except (OSError, ValueError):
        with args.ledger.open("rb+") as handle:
            handle.truncate(original_size)
        applied_path(args.draft).unlink(missing_ok=True)
        raise
    checked_path(args.draft).unlink()
    print(f"{len(active)} Buchungen übernommen und mit hledger check geprüft."
          " Nach Ledger-Abgleich mit 'cleanup' temporäre Quellen entfernen.")


def cleanup(args):
    if args.draft.is_symlink():
        raise ValueError("Der Entwurf darf für cleanup kein Symlink sein")
    rows = load_draft(args.draft)
    marker = applied_path(args.draft)
    digest = hashlib.sha256(args.draft.read_bytes()).hexdigest()
    if not marker.is_file() or marker.read_text(encoding="ascii").strip() != digest:
        raise ValueError("Kein passender Übernahmevermerk. Zuerst 'check' und 'apply' ausführen")
    inbox = args.inbox.resolve()
    if not inbox.is_dir():
        raise ValueError(f"Temporärer Eingangsordner fehlt: {inbox}")
    sources = []
    for source in sorted({row["source"] for row in rows}):
        if not source or Path(source).name != source:
            raise ValueError(f"Ungültiger Quelldateiname im Entwurf: {source!r}")
        file = inbox / source
        if file.is_symlink() or file.resolve().parent != inbox:
            raise ValueError(f"Quelle außerhalb des Eingangsordners: {source}")
        if file.is_file():
            sources.append(file)
    print("Temporäre Dateien zum Entfernen:")
    for file in sources:
        print("  ", file)
    print("  ", args.draft)
    if bank_import.prompt("Nach Kontrolle des Ledgers wirklich löschen? Tippe LÖSCHEN") != "LÖSCHEN":
        print("Abgebrochen; nichts gelöscht.")
        return
    for file in sources:
        file.unlink()
    args.draft.unlink()
    marker.unlink()
    print(f"{len(sources)} Quellen und Entwurf entfernt; das Ledger bleibt unverändert.")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    prep = commands.add_parser("prepare", help="CSV/ZIP, Bank-PDFs und Bilder im Eingangsordner automatisch erkennen")
    prep.add_argument("--statement", type=Path, action="append", default=[], help="CSV/ZIP oder Bank-PDF, mehrfach angebbar")
    prep.add_argument("--image", type=Path, action="append", default=[])
    prep.add_argument("--inbox", type=Path, default=WORK_DIR / "inbox", help="Eingangsordner für automatische Erkennung")
    prep.add_argument("--draft", type=Path, default=WORK_DIR / "drafts/bank-draft.tsv")
    prep.add_argument("--ledger", type=Path, default=Path.home() / "Ledger/main_2025.ledger", help="Ledger für lokale Bankkonto-Vorschläge")
    prep.add_argument("--account-map", type=Path, default=WORK_DIR / "account-map.json", help="Private, lokal gemerkte Bankkonto-Zuordnungen")
    prep.add_argument("--ocr-lang", default="eng", help="Installierte Tesseract-Sprachen, z.B. eng+deu+slk")
    for name in ("check", "apply"):
        sub = commands.add_parser(name, help="Entwurf mit hledger abgleichen" if name == "check" else "Geprüften Entwurf übernehmen")
        sub.add_argument("draft", type=Path)
        sub.add_argument("ledger", type=Path)
        sub.add_argument("--days", type=int, default=2)
    clean = commands.add_parser("cleanup", help="Nach geprüfter Übernahme temporäre Quellen und Entwurf löschen")
    clean.add_argument("draft", type=Path)
    clean.add_argument("--inbox", type=Path, default=WORK_DIR / "inbox")
    args = parser.parse_args(argv)
    try:
        if args.command == "prepare":
            prepare(args)
        elif args.command == "cleanup":
            cleanup(args)
        else:
            verify(args, apply=args.command == "apply")
        return 0
    except (OSError, ValueError, subprocess.SubprocessError, EOFError) as exc:
        print(f"Fehler: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
