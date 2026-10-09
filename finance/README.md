# Lokaler Bankimport

`stow -t "$HOME" finance` verlinkt die Importskripte und den Befehl
`bank-workflow` nach `~/.local/bin`. Auszüge, Ledger, Entwürfe und PDF-Passwörter gehören **nicht**
in dieses öffentliche Git-Repository.

Benötigt werden Python 3 und `pypdf` für die PDFs; für Raiffeisen außerdem
`pdftotext` (Poppler), für Screenshots `tesseract` und für Prüfung/Übernahme
`hledger`. Tatra-PDF-Passwörter werden verdeckt im Terminal abgefragt.

```sh
bank-workflow prepare \
  --statement /pfad/zum/wise-export.pdf \
  --statement /pfad/zum/raiffeisen-auszug.pdf \
  --statement /pfad/zum/tatra-auszug.pdf \
  --draft "$HOME/Ledger/imports/bank-draft.tsv"

nvim "$HOME/Ledger/imports/bank-draft.tsv"
bank-workflow check "$HOME/Ledger/imports/bank-draft.tsv" "$HOME/Ledger/main_2025.ledger"
bank-workflow apply "$HOME/Ledger/imports/bank-draft.tsv" "$HOME/Ledger/main_2025.ledger"
```

`action` ist `add`, `skip` oder (bei geprüften Duplikatverdachtsfällen) `add!`.
`amount` ist die Bewegung auf `bank_account`; `counter_account` ist die zweite
Buchungsseite. Bei einer Umbuchung steht dort das andere Bankkonto; eine
zweite importierte Bankzeile für denselben Transfer wird `skip`. Für einen
Währungswechsel auch `counter_amount` und `counter_currency` ausfüllen.

Im Neovim-Entwurf liefert `<C-x><C-o>` bzw. `<C-Space>` lokale Kontovorschläge
aus `hledger accounts`. Das Plugin nutzt zuerst `LEDGER_FILE` oder
`vim.g.bank_import_ledger`, dann `~/Ledger/main_2025.ledger`, falls vorhanden.
Das Ledger muss beim Bearbeiten lokal zugänglich sein.
