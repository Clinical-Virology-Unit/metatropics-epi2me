# Metatropics-epi2me

Metatropics is a Nextflow pipeline for Oxford Nanopore metagenomic data. It detects viral pathogens in complex samples and, where coverage allows, builds viral consensus genomes and variant calls. Metatropics-epi2me is the EPI2ME Desktop version of that workflow.

For command-line runs, HPC, and full documentation, use the main pipeline: **[Clinical-Virology-Unit/Metatropics](https://github.com/Clinical-Virology-Unit/Metatropics)**.

## Run in EPI2ME Desktop

1. Install [EPI2ME Desktop](https://epi2me.nanoporetech.com/epi2me-docs/installation/).
2. Install Docker and Nextflow — follow [Metatropics §2 Java and Nextflow](https://github.com/Clinical-Virology-Unit/Metatropics#2-java-and-nextflow) and [§3 Containers](https://github.com/Clinical-Virology-Unit/Metatropics#3-containers).
3. Import workflow: https://github.com/clinical-virology-unit/metatropics-epi2me
4. Set input mode and reads folder:
   - pod5 — basecall + demultiplex in pipeline (NVIDIA GPU required)
   - fastq_pass — on-device basecalled, demultiplex in pipeline
   - demultiplexed_fastq — per-sample FASTQ files or barcodeXX/ folders
5. Sample sheet: yes for pod5 or fastq_pass ([templates](https://github.com/clinical-virology-unit/metatropics-epi2me/blob/main/assets/README.md)); leave blank for demultiplexed_fastq
6. Optional: Virasign database (RVDB/Refseq/Custom), host depletion, and other advanced options (e.g. keep Reads or BAM outputs)
7. Nextflow configuration: profile standard (= Docker). Leave Configuration empty.

### Outputs

After a run you get three folders:

| Folder | What it is |
|--------|------------|
| Summary/ | Summary report — viruses identified per sample, coverage, read counts |
| Consensus/ | Consensus viral genomes (FASTA) |
| Variant_calling/ | Variant calls (VCF + HTML report per virus) |

By default, intermediate folders Reads/ and Classification/ are not kept in EPI2ME runs. In Advanced options, enable Reads and/or BAM independently if you need QC/host-depleted FASTQs or Virasign classification BAMs. For a full description of every output file, see the [Metatropics output guide](https://github.com/Clinical-Virology-Unit/Metatropics/blob/main/nf-metatropics/assets/output/README.md).

## Citation

If you use Metatropics in your research, please cite:

```
Jansen, D., De Souza Novaes, A., de Block, T., Rezende, A. M., & Vercauteren, K. (2026). Metatropics Human viral pathogen identification and consensus genome calling from nanopore metagenomic sequencing data. (v0.1.1). Zenodo. https://doi.org/10.5281/zenodo.20430617
```

Also cite the tools you use (Nextflow, Virasign, Clair3, etc.); see [Metatropics CITATIONS.md](https://github.com/Clinical-Virology-Unit/Metatropics/blob/main/nf-metatropics/assets/citing/CITATIONS.md).
