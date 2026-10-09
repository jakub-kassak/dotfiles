# Lokaler Bankimport

`stow -t "$HOME" finance` verlinkt die Importskripte und den Befehl
`bank-workflow` nach `~/.local/bin`. Auszüge, Ledger, Entwürfe und PDF-Passwörter gehören **nicht**
in dieses öffentliche Git-Repository.

Benötigt werden Python 3 und `pypdf` für die PDFs; für Raiffeisen außerdem
`pdftotext` (Poppler), für Screenshots `tesseract` und für Prüfung/Übernahme
`hledger`. Tatra-PDF-Passwörter werden verdeckt im Terminal abgefragt.
Originalexporte liegen bis zur Übernahme privat unter
`~/Library/Application Support/BankWorkflow/inbox`, Entwürfe unter
`~/Library/Application Support/BankWorkflow/drafts`. Beide Ordner liegen nur
auf diesem Mac, außerhalb von Git und des mit Syncthing verbundenen Ledgers.
Das Ledger selbst bleibt unter `~/Ledger`.

```sh
WORKFLOW="$HOME/Library/Application Support/BankWorkflow"
bank-workflow prepare

nvim "$WORKFLOW/drafts/bank-draft.tsv"
bank-workflow check "$WORKFLOW/drafts/bank-draft.tsv" "$HOME/Ledger/main_2025.ledger"
bank-workflow apply "$WORKFLOW/drafts/bank-draft.tsv" "$HOME/Ledger/main_2025.ledger"
# Nach eigener Kontrolle des Ledgers und seiner Synchronisierung:
bank-workflow cleanup "$WORKFLOW/drafts/bank-draft.tsv"
```

`prepare` findet CSV-, ZIP- und PDF-Auszüge sowie Screenshots direkt in `inbox`
(auch ein falsch benanntes ZIP mit `.pdf`-Endung). Es legt den privaten
Entwurfsordner bei Bedarf selbst an. Mit wiederholtem `--statement DATEI`
bzw. `--image DATEI` können stattdessen gezielt einzelne Dateien gewählt
werden; `--inbox PFAD` ändert den Suchordner. `cleanup`
löscht nur die im erfolgreich übernommenen Entwurf genannten Eingangsdateien,
den Entwurf und dessen Übernahmevermerk; es fragt vorher nochmals nach.

`action` ist `add`, `skip` oder (bei geprüften Duplikatverdachtsfällen) `add!`.
`amount` ist die Bewegung auf `bank_account`; `counter_account` ist die zweite
Buchungsseite. Bei einer Umbuchung steht dort das andere Bankkonto; eine
zweite importierte Bankzeile für denselben Transfer wird `skip`. Für einen
Währungswechsel auch `counter_amount` und `counter_currency` ausfüllen.

Im Neovim-Entwurf liefert `<C-x><C-o>` bzw. `<C-Space>` lokale Kontovorschläge
aus `hledger accounts`. Das Plugin nutzt zuerst `LEDGER_FILE` oder
`vim.g.bank_import_ledger`, dann `~/Ledger/main_2025.ledger`, falls vorhanden.
Das Ledger muss beim Bearbeiten lokal zugänglich sein.
