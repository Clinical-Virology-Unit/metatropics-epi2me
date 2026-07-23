#!/usr/bin/env nextflow
/* clinical-virology-unit/metatropics-epi2me — EPI2ME Desktop workflow */

nextflow.enable.dsl = 2

def epi2meInput = Epi2meParams.apply(params, projectDir.toString(), log)
if (epi2meInput) {
    params.epi2me_samplesheet = epi2meInput
}
if (params.virasign_db_source?.toString()?.trim()) {
    log.info "Virasign database: ${VirasignDb.effectiveDatabase(params)} (source=${VirasignDb.dbSource(params)})"
}

def samplesheet = params.input ?: params.epi2me_samplesheet
def outdir = params.outdir ?: params.out_dir

if (!samplesheet) {
    log.error "No input samplesheet. Use --reads and --input_mode (EPI2ME), or --input with a CSV samplesheet."
    System.exit(1)
}

if (!outdir) {
    log.error "No output directory. Set --out_dir or --outdir."
    System.exit(1)
}

log.info "Metatropics-epi2me ${workflow.manifest.version} | input=${samplesheet} | outdir=${outdir}"

include { METATROPICS } from './workflows/metatropics'

workflow {
    METATROPICS ()
}
