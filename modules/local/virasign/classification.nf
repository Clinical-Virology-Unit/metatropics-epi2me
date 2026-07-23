process VIRASIGN_CLASSIFICATION {
    tag "Viral classification"
    label 'process_medium'

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'library://jansendaan94_v2/metatropics/virasign:latest':
        'daanjansen94/virasign:latest' }"

    // Bind the shared Databases tree; virasign --db-dir may be a per-accession subfolder for Custom.
    def pipelineRoot = projectDir.toString()
    def db_root = VirasignDb.databaseDir(params, pipelineRoot)
    def virasign_db_dir = VirasignDb.virasignDbDir(params, pipelineRoot)
    def dbAbs = file(db_root).toAbsolutePath().toString()

    // Ensure any user-provided control/blind files are visible in-container.
    def extraBindDirs = []
    def addBindDir = { String p ->
        if (!p) return
        def fp = file(p)
        def d = fp.isDirectory() ? fp : fp.parent
        if (d != null) extraBindDirs << d.toAbsolutePath().toString()
    }
    def zc = params.virasign_zscore_controls?.toString()?.trim()
    if (zc) {
        zc.split(',').collect { it.trim() }.findAll { it }.each { addBindDir(it) }
    }
    addBindDir(params.virasign_blind?.toString()?.trim())
    extraBindDirs = extraBindDirs.unique()

    if (workflow.containerEngine == 'docker' || workflow.containerEngine == 'podman') {
        def extra = extraBindDirs.collect { " -v ${it}:${it}" }.join('')
        containerOptions "-v ${dbAbs}:${dbAbs}${extra}"
    }
    if (workflow.containerEngine == 'singularity' || workflow.containerEngine == 'apptainer') {
        def extra = extraBindDirs.collect { " --bind ${it}:${it}" }.join('')
        containerOptions "--bind ${dbAbs}:${dbAbs}${extra}"
    }

    input:
    path db_ready
    tuple val(meta), path(virasign_input_fastqs)

    output:
    path "publish/**",                          emit: results
    path "hits.tsv",                             emit: hits_tsv
    path "versions.yml",                       emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    // Ensure host DB dir exists before the container writes into it.
    file(db_root).mkdirs()
    def threads = params.virasign_threads ?: task.cpus
    def opt = []
    def add = { c, f -> if (c) opt << f }

    def rawDbArg = VirasignDb.effectiveDatabase(params)
    def effectiveDbArg = rawDbArg ?: 'RVDB'
    // Use projectDir.toString() (not process-scoped pipelineRoot) on def RHS — Nextflow 23.04.
    def dbLayout = VirasignDb.dbLayout(params, projectDir.toString())
    def dbMarkerPath = dbLayout.marker
    def legacyMarkerPath = dbLayout.legacy_marker ?: ''
    // Output isolation per database choice (avoid mixing when using -resume).
    def virasignDbLabel = VirasignDb.dbLabel(params)
    def resolvedDbArg = effectiveDbArg
    def markerFile = file(dbMarkerPath)
    if (!markerFile.exists() && legacyMarkerPath) {
        markerFile = file(legacyMarkerPath)
    }
    if (markerFile.exists()) {
        def fastaLine = markerFile.readLines().find { it.startsWith('fasta_path=') }
        if (fastaLine) {
            def fastaPath = fastaLine.substring('fasta_path='.length())
            if (file(fastaPath).exists()) {
                if (VirasignDb.isCustomAccessionDb(params)) {
                    // Custom DBs live under Custom/<accession>/; pass the prepared FASTA path.
                    resolvedDbArg = fastaPath
                } else {
                    resolvedDbArg = fastaPath
                    if (VirasignDb.passAccessionsArg(params) && fastaPath.endsWith('_complete.fasta') && !fastaPath.contains('_with_accessions')) {
                        def withAcc = fastaPath.replace('_complete.fasta', '_complete_with_accessions.fasta')
                        if (file(withAcc).exists()) {
                            resolvedDbArg = withAcc
                        }
                    }
                }
            }
        }
    } else if (effectiveDbArg) {
        def lower = effectiveDbArg.toLowerCase()
        if (lower == 'refseq') {
            // No `def` here: Nextflow 23.04 errors on `def x = "${db_root}/..."` when db_root
            // was already declared in the process (directive) scope.
            refseqFasta = file("${db_root}/RefSeq/viral_refseq_complete.fna")
            if (refseqFasta.exists()) {
                resolvedDbArg = refseqFasta.toAbsolutePath().toString()
            }
        } else if (lower == 'rvdb') {
            rvdbDir = file("${db_root}/RVDB")
            if (rvdbDir.exists()) {
                def candidates = null
                if (VirasignDb.passAccessionsArg(params)) {
                    candidates = rvdbDir.listFiles()?.findAll { it.name ==~ /^RVDB.*_complete_with_accessions\.fasta$/ }
                }
                if (!candidates) {
                    candidates = rvdbDir.listFiles()?.findAll { it.name ==~ /^RVDB.*_complete\.fasta$/ && !it.name.contains('_with_accessions') }
                }
                if (candidates) {
                    resolvedDbArg = candidates.sort { it.name }.last().toAbsolutePath().toString()
                }
            }
        } else if (VirasignDb.isCustomAccessionDb(params)) {
            def accDir = file(dbLayout.subdir as String)
            if (accDir.exists()) {
                def stem = effectiveDbArg.replaceAll(/\\.[^.]+$/, '')
                def candidates = ['fasta', 'fna', 'fa'].collectMany { ext ->
                    [file("${accDir}/${effectiveDbArg}.${ext}"), file("${accDir}/${stem}.${ext}")]
                }.findAll { it.exists() }
                if (candidates) {
                    resolvedDbArg = candidates[0].toAbsolutePath().toString()
                }
            }
        }
    }

    add(resolvedDbArg, "-d '${resolvedDbArg}'")
    add(VirasignDb.passRvdbVersionArg(params), "--rvdb-version ${params.virasign_rvdb_version}")
    extraAccessions = VirasignDb.additionalAccessionsArg(params)
    add(extraAccessions as boolean, "-a '${extraAccessions}'")
    add(params.virasign_ultrasensitive == true, '-u')
    add(params.virasign_min_identity != null, "--min_identity ${params.virasign_min_identity}")
    add(params.virasign_min_mapped_reads != null, "--min_mapped_reads ${params.virasign_min_mapped_reads}")
    add(params.virasign_coverage_depth != null, "--coverage_depth ${params.virasign_coverage_depth}")
    add(params.virasign_coverage_breadth != null, "--coverage_breadth ${params.virasign_coverage_breadth}")
    add(params.virasign_min_nogr != null, "--min-nogr ${params.virasign_min_nogr}")
    add(true, '--no-html')
    add(params.virasign_no_gzip_fastq == true, '--no-gzip-fastq')
    add(!!params.virasign_zscore, "--zscore ${params.virasign_zscore}")
    add(params.virasign_zscore_controls?.toString()?.trim(), "--zscore-controls '${params.virasign_zscore_controls}'")
    add(params.virasign_blind?.toString()?.trim(), "-b '${params.virasign_blind}'")

    def tail = task.ext.args?.toString()?.trim()
    // No `def`: interpolates process-scoped virasign_db_dir (Nextflow 23.04).
    cmd = (['virasign', '-i', 'virasign_in', '-o', 'publish', "--db-dir", "${virasign_db_dir}", '-t', "${threads}"] + opt + (tail ? [tail] : [])).join(' ')
    """
    # Barrier input from DB prep (validates on-host database before classification).
    test -f "${db_ready}"
    if [ ! -f "${dbMarkerPath}" ] && { [ -z "${legacyMarkerPath}" ] || [ ! -f "${legacyMarkerPath}" ]; }; then
      echo "ERROR: Virasign database marker missing under ${db_root}; restart with -resume." >&2
      exit 1
    fi
    echo "Virasign classification -d=${resolvedDbArg}"

    mkdir -p virasign_in

    # Stage input FASTQs into virasign_in/ (accept file or dir). Prefer canonical sample ID.
    stage_one () {
      local f="\$1"
      [ -e "\$f" ] || return 0

      local base="\${f##*/}"
      base="\${base%.fastq.gz}"
      base="\${base%.fq.gz}"
      base="\${base%_other}"

      local out="${meta.id}.fastq.gz"
      # If multiple files are provided, avoid name collisions.
      if [ -e "virasign_in/\$out" ]; then
        out="\${base}.fastq.gz"
      fi
      # Use absolute symlinks (workdir inputs may be symlinks themselves).
      target=\$(readlink -f "\$f" 2>/dev/null || realpath "\$f" 2>/dev/null || echo "\$f")
      ln -sfn "\$target" "virasign_in/\$out"
    }

    for f in ${virasign_input_fastqs}; do
      [ -e "\$f" ] || continue
      if [ -d "\$f" ]; then
        # Link all FASTQs in the directory.
        while IFS= read -r -d '' fq; do
          stage_one "\$fq"
        done < <(find "\$f" -maxdepth 1 -type f \\( -name '*.fastq' -o -name '*.fq' -o -name '*.fastq.gz' -o -name '*.fq.gz' \\) -print0)
      else
        stage_one "\$f"
      fi
    done

    n=\$(find virasign_in -maxdepth 1 -type l \\( -name '*.fastq' -o -name '*.fq' -o -name '*.fastq.gz' -o -name '*.fq.gz' \\) | wc -l)
    if [ "\$n" -eq 0 ]; then
      echo "ERROR: no FASTQs staged into virasign_in (input resolved to a directory with no FASTQ files, or empty optional upstream output)." >&2
      ls -la virasign_in >&2 || true
      exit 1
    fi
    ${cmd}

    # Create per-virus mask BEDs alongside Virasign BAMs.
    # These are later used to N-mask consensus sequences.
    #
    # IMPORTANT: We enforce:
    # - minimum depth (`params.depth`, default 25)
    # - minimum base quality and mapping quality matching Clair3 uniform recount
    #   (`params.clair3_min_bq` / `params.clair3_min_mq`)
    #
    # This keeps site masking conceptually aligned with variant calling thresholds
    # (Clair3 uses --qual / --min_mq during calling; we at least mirror base-Q here).
    MIN_DEPTH="${params.depth ?: 25}"
    MIN_BQ="${params.clair3_min_bq ?: 15}"
    MIN_MQ="${params.clair3_min_mq ?: 15}"
    if command -v samtools >/dev/null 2>&1; then
      while IFS= read -r -d '' bam; do
        bai="\${bam}.bai"
        if [ ! -e "\$bai" ] && [ -e "\${bam%.bam}.bam.bai" ]; then
          bai="\${bam%.bam}.bam.bai"
        fi
        samtools index "\$bam" >/dev/null 2>&1 || true
        # Compute depth after filtering low-quality bases:
        # -Q MIN_BQ filters bases by Phred base quality
        # mpileup depth is column 4 (coverage) in samtools output
        ref="\${bam%.bam}.fasta"
        if [ ! -e "\$ref" ]; then
          # Fallback: keep old behaviour (depth-only) if reference isn't present for mpileup.
          samtools depth -aa -d 0 "\$bam" \
            | awk -v min="\$MIN_DEPTH" 'BEGIN{OFS="\\t"} { if(\$3 < min) print \$1, \$2-1, \$2 }' \
            > "\${bam%.bam}.bed"
        else
          samtools mpileup -aa -d 0 -Q "\$MIN_BQ" -q "\$MIN_MQ" -f "\$ref" "\$bam" 2>/dev/null \
            | awk -v min="\$MIN_DEPTH" 'BEGIN{OFS="\\t"} { if(\$4 < min) print \$1, \$2-1, \$2 }' \
            > "\${bam%.bam}.bed"
        fi
      done < <(find publish -type f -name '*.bam' -print0)
    else
      echo "WARNING: samtools not found in Virasign container; depth mask BEDs will not be generated." >&2
    fi

    # One TSV row per confident hit (same folder layout as Virasign: publish/<sample>/<acc>/).
    python3 <<PY
    import json, os, re, sys

    publish_dir = "publish"
    sample_id = "${meta.id}"
    sample_dir = os.path.join(publish_dir, sample_id)
    candidates = []
    if os.path.isdir(sample_dir):
        candidates.append(os.path.join(sample_dir, "%s_final_selected_references.json" % sample_id))
        for fn in os.listdir(sample_dir):
            if fn.endswith("_final_selected_references.json"):
                candidates.append(os.path.join(sample_dir, fn))
    candidates = [c for c in candidates if os.path.exists(c)]
    final_json = os.path.join(sample_dir, "%s_final_selected_references.json" % sample_id)
    if not candidates:
        # No confident hits: still emit an empty final-selected JSON so publishDir and
        # virasign --build-html include this sample in the Metatropics summary (negative row).
        os.makedirs(sample_dir, exist_ok=True)
        with open(final_json, "w") as fh:
            json.dump([], fh)
        open("hits.tsv", "w").close()
        sys.exit(0)
    final_json = candidates[0]

    with open(final_json) as fh:
        hits = json.load(fh)

    def slug(s):
        s = (s or "").strip()
        if not s:
            return ""
        s = re.sub(r"[^A-Za-z0-9._-]+", "_", s)
        s = s.lstrip("_").rstrip("_")
        s = re.sub(r"_+", "_", s)
        return s

    out = open("hits.tsv", "w")
    for hit in hits:
        acc = str(hit.get("accession", "") or "").strip()
        if not acc:
            continue
        raw_sp = (hit.get("organism") or hit.get("viral_species") or "").strip()
        if (not raw_sp) and hit.get("description"):
            raw_sp = str(hit["description"]).strip()[:120]
        sp_slug = slug(raw_sp)
        virus_slug = "%s_%s" % (acc, sp_slug) if sp_slug else acc
        ref_fasta = os.path.join(os.path.dirname(final_json), acc, "%s.fasta" % acc)
        if not os.path.exists(ref_fasta):
            continue
        out.write("\\t".join([sample_id, acc, virus_slug, sp_slug, os.path.realpath(ref_fasta)]) + "\\n")
    out.close()
    PY

    # Don't propagate per-run virasign log into shared results.
    rm -f publish/.virasign.log || true

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        virasign: \$(virasign --version 2>&1 | head -n1 || echo 'unknown')
    END_VERSIONS
    """
}

