# Sample sheets (EPI2ME)

Columns are always **`sample`**, then either **`barcode`** or **`well`** (TWIST plates).

## When do you need a sample sheet?

| Input mode | Reads selection | Sample sheet |
|------------|-----------------|--------------|
| `demultiplexed_fastq` | `pass/` with `barcodeNN/` folders | real sample names |
| `demultiplexed_fastq` | single demultiplexed FASTQs folder | real sample names |
| `fastq_pass` | Undemultiplexed `fastq_pass/` | `sample,barcode` or `sample,well` |
| `pod5` | POD5 folder | `sample,barcode` or `sample,well` |

Build sheets with **`metatropics-samplesheet`**:

```bash
cd epi2melabs/workflows/clinical-virology-unit/metatropics-epi2me
pip install .

# 1. demultiplexed (pass/ with barcodeNN/)
metatropics-samplesheet demultiplexed TWIST-96A-UDI -o wells.csv
metatropics-samplesheet demultiplexed -i pass --kit TWIST-96A-UDI --wells wells.csv -o samplesheet.csv

# 2. fastq_pass
metatropics-samplesheet fastq_pass TWIST-96A-UDI -o wells.csv
metatropics-samplesheet fastq_pass TWIST-96A-UDI wells.csv -o fastq_pass.csv

# 3. POD5
metatropics-samplesheet pod5 TWIST-96A-UDI -o wells.csv
metatropics-samplesheet pod5 TWIST-96A-UDI wells.csv -o POD5.csv
```

## Templates

| File | Columns | Use |
|------|---------|-----|
| [`demultiplexed.csv`](demultiplexed.csv) | `sample`, `barcode` | Demultiplexed `pass/` — barcode labels matching `barcodeNN/` folders |
| [`fastq_pass.csv`](fastq_pass.csv) | `sample`, `barcode` | fastq_pass — barcode labels |
| [`POD5.csv`](POD5.csv) | `sample`, `barcode` | POD5 — barcode labels |
| [`wells.csv`](wells.csv) / [`POD5_wellID.csv`](POD5_wellID.csv) | `sample`, `well` | TWIST well IDs — usable **alone** in EPI2ME if **`kit_name`** matches the plate |

Either form works in EPI2ME:

- **`sample,barcode`** — barcode labels (`barcode01` …); no well conversion
- **`sample,well`** (`wells.csv`) — lab well IDs; set `kit_name` (e.g. `TWIST-96A-UDI`) and EPI2ME maps well → `barcodeNN` automatically (no need to pre-build `POD5.csv` / `fastq_pass.csv`)
