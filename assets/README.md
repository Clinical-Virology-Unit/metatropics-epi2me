# Sample sheets (EPI2ME)

Columns are always **`sample`**, then either **`barcode`** or **`well`** (TWIST plates).

## When do you need a sample sheet?

| Input mode | Reads selection | Sample sheet |
|------------|-----------------|--------------|
| `demultiplexed_fastq` | MinKNOW/Dorado **`pass/`** (`barcodeNN/` folders) | **Recommended** — real sample names. Leave blank only if sample IDs may stay as `barcode35`, … |
| `demultiplexed_fastq` | **Single FASTQ file** | Optional (one sample) |
| `fastq_pass` | Undemultiplexed `fastq_pass/` (or run folder) | Recommended — `sample,barcode` or `sample,well` |
| `pod5` | POD5 folder | Recommended — `sample,barcode` or `sample,well` |

Build sheets with **`metatropics-samplesheet`** (from this repo: `pip install -e .`):

```bash
# Demultiplexed pass/ + TWIST wells from the lab
metatropics-samplesheet demultiplexed TWIST-96A-UDI -o wells.txt
# edit wells.txt → sample,well
metatropics-samplesheet demultiplexed -i pass --kit TWIST-96A-UDI --wells wells.txt -o .
# → samplesheet.csv for EPI2ME (Reads = pass/, Sample sheet = samplesheet.csv)

# Or a simple label sheet (GUI-friendly):
# sample,barcode
# PatientA,barcode35
# PatientB,barcode36

# POD5 / fastq_pass
metatropics-samplesheet pod5 TWIST-96A-UDI wells.txt -o POD5.csv
metatropics-samplesheet fastq_pass TWIST-96A-UDI wells.txt -o fastq_pass.csv
```

Missing barcodes under `pass/` are skipped (not every well is sequenced).

## Templates

| File | Columns | Use |
|------|---------|-----|
| [`demultiplexed.csv`](demultiplexed.csv) | `sample`, `barcode` | Demultiplexed `pass/` — barcode **labels** (`barcode35`) matching folder names |
| [`POD5.csv`](POD5.csv) | `sample`, `barcode` | POD5 / fastq_pass — barcode labels |
| [`POD5_wellID.csv`](POD5_wellID.csv) | `sample`, `well` | TWIST plate well IDs (`A01` …); set matching `kit_name` |

## TWIST `kit_name`

| Plate | kit_name |
|-------|----------|
| A | `TWIST-96A-UDI` |
| B | `TWIST-96B-UDI` |
| C | `TWIST-96C-UDI` |
| D | `TWIST-96D-UDI` |

Well→barcode index is `barcode01`–`barcode96` on every plate; the kit selects which oligo set Dorado uses (POD5/fastq_pass). For demultiplexed data the kit is only needed when converting **well IDs** in `wells.txt` / a well column.
