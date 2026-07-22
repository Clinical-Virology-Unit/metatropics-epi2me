# Sample sheets (EPI2ME)

**When do you need one?**

| Input mode | Sample sheet |
|------------|--------------|
| `demultiplexed_fastq` | No — leave blank |
| `fastq_pass` | Optional — custom sample names |
| `pod5` | Optional — custom sample names |

Use columns `sample` then `barcode` or `well` (TWIST plates).

## Templates

| File | Columns | Example |
|------|---------|---------|
| [`POD5.csv`](POD5.csv) | `sample`, `barcode` | `Sample1`, `barcode01` |
| [`POD5_wellID.csv`](POD5_wellID.csv) | `sample`, `well` | `Patient_A`, `A01` |

For TWIST 96-well plates, set kit_name to match your plate:

### TWIST kit_name

| Plate | kit_name |
|-------|------------|
| A | `TWIST-96A-UDI` |
| B | `TWIST-96B-UDI` |
| C | `TWIST-96C-UDI` |
| D | `TWIST-96D-UDI` |
