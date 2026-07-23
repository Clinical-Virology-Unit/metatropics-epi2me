process VIRASIGN_DB {
    tag "Create viral database"
    label 'process_medium'
    cache false

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'library://jansendaan94_v2/metatropics/virasign:latest':
        'daanjansen94/virasign:latest' }"

    // Bind the shared Databases tree (RVDB, Human, per-accession Custom, …).
    def pipelineRoot = projectDir.toString()
    def db_root = VirasignDb.databaseDir(params, pipelineRoot)
    def layout = VirasignDb.dbLayout(params, pipelineRoot)
    def virasign_db_dir = VirasignDb.virasignDbDir(params, pipelineRoot)
    def dbAbs = file(db_root).toAbsolutePath().toString()
    if (workflow.containerEngine == 'docker' || workflow.containerEngine == 'podman') {
        containerOptions "-v ${dbAbs}:${dbAbs}"
    }
    if (workflow.containerEngine == 'singularity' || workflow.containerEngine == 'apptainer') {
        containerOptions "--bind ${dbAbs}:${dbAbs}"
    }

    output:
    path "db_ready.txt", emit: ready
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    file(db_root).mkdirs()
    // Custom: Virasign stages flat files under Custom/ first; only create Custom/<acc>/
    // when we move them (avoids an empty KC….1/ folder during download).
    if (layout.kind == 'custom') {
        if (layout.custom_staging) {
            file(layout.custom_staging).mkdirs()
        }
    } else {
        file(layout.subdir).mkdirs()
    }
    def opt = []
    def add = { c, f -> if (c) opt << f }

    def effectiveDbArg = VirasignDb.effectiveDatabase(params)
    add(effectiveDbArg, "-d '${effectiveDbArg}'")
    // Only for RVDB — never pass --rvdb-version when preparing RefSeq/Custom.
    add(VirasignDb.passRvdbVersionArg(params), "--rvdb-version ${params.virasign_rvdb_version}")
    // Custom: first accession is -d; further accessions are -a (merged custom FASTA).
    // RVDB/RefSeq: all accessions are -a. Never imply -d RVDB for Custom.
    extraAccessions = VirasignDb.additionalAccessionsArg(params)
    add(extraAccessions as boolean, "-a '${extraAccessions}'")
    // Clustering only applies to RVDB.
    add(VirasignDb.dbSource(params) == 'RVDB' && params.virasign_enable_clustering == true, '--enable-clustering')
    add(VirasignDb.dbSource(params) == 'RVDB' && params.virasign_cluster_identity != null, "--cluster_identity ${params.virasign_cluster_identity}")
    add(params.virasign_max_ambiguous_fraction != null, "--max-ambiguous-fraction ${params.virasign_max_ambiguous_fraction}")

    def tail = task.ext.args?.toString()?.trim()
    // No `def`: interpolates process-scoped virasign_db_dir (Nextflow 23.04).
    cmd = (['virasign', '--prepare-db', "--db-dir", "${virasign_db_dir}"] + opt + (tail ? [tail] : [])).join(' ')

    // Nextflow 23.04: do not `def x = layout.*` after process-scoped `layout` (VariableVisitor).
    marker = layout.marker
    subdir = layout.subdir
    min_bytes = layout.min_bytes
    fp_hash = VirasignDb.markerFingerprintHash(params)
    db_kind = layout.kind
    fasta_rel = layout.fasta_rel ?: ''
    accessions = extraAccessions ?: ''
    custom_accession = layout.accession ?: ''
    custom_staging = layout.custom_staging ?: ''
    legacy_marker = layout.legacy_marker ?: ''
    db_source = VirasignDb.dbSource(params)

    """
    set -euo pipefail

    DB_DIR="${db_root}"
    DB_SUBDIR="${subdir}"
    MARKER="${marker}"
    LEGACY_MARKER="${legacy_marker}"
    MIN_BYTES=${min_bytes}
    FP_HASH="${fp_hash}"
    DB_KIND="${db_kind}"
    DB_SOURCE="${db_source}"
    FASTA_REL="${fasta_rel}"
    ACCESSIONS="${accessions}"
    CUSTOM_ACCESSION="${custom_accession}"
    CUSTOM_STAGING="${custom_staging}"

    echo "Virasign prepare-db source=\${DB_SOURCE} kind=\${DB_KIND} -d=${effectiveDbArg}"
    case "\$DB_SOURCE" in
      CUSTOM)
        if echo "${effectiveDbArg}" | grep -Eiq '^(RVDB|REFSEQ)\$'; then
          echo "ERROR: Custom mode refused to prepare named DB '${effectiveDbArg}' (would pull RVDB/RefSeq)." >&2
          exit 1
        fi
        ;;
      REFSEQ)
        if echo "${effectiveDbArg}" | grep -Eiq '^RVDB\$'; then
          echo "ERROR: RefSeq mode refused to prepare RVDB." >&2
          exit 1
        fi
        ;;
    esac

    cleanup_wrong_custom_roots () {
      [ "\$DB_KIND" = "custom" ] || return 0
      local wrong="\${DB_DIR}/\${CUSTOM_ACCESSION}"
      if [ -d "\$wrong" ]; then
        echo "Removing erroneous layout \${wrong} (custom DBs live under \${CUSTOM_STAGING}/\${CUSTOM_ACCESSION})..." >&2
        rm -rf "\$wrong"
      fi
    }

    organize_custom_from_staging () {
      [ "\$DB_KIND" = "custom" ] || return 0
      local stem="\${CUSTOM_ACCESSION%%.*}"
      local base f src
      mkdir -p "\$DB_SUBDIR"
      for src in "\$CUSTOM_STAGING" \
                 "\${DB_DIR}/\${CUSTOM_ACCESSION}/Custom" \
                 "\${DB_DIR}/\${CUSTOM_ACCESSION}/Databases/Custom"; do
        [ -d "\$src" ] || continue
        for base in "\${CUSTOM_ACCESSION}.fasta" "\${stem}.fasta" "\${CUSTOM_ACCESSION}.fna" "\${stem}.fna"; do
          f="\$src/\$base"
          if [ -f "\$f" ]; then
            mv "\$f" "\$DB_SUBDIR/"
          fi
        done
        for f in "\$src/\${stem}.fasta.mmi" "\$src/\${CUSTOM_ACCESSION}.fasta.mmi"; do
          if [ -f "\$f" ]; then
            mv "\$f" "\$DB_SUBDIR/"
          fi
        done
        if [ -d "\$src/taxonomy" ] && [ ! -e "\$DB_SUBDIR/taxonomy" ]; then
          mv "\$src/taxonomy" "\$DB_SUBDIR/"
        fi
      done
    }

    cleanup_custom_staging_root () {
      [ "\$DB_KIND" = "custom" ] || return 0
      local stem="\${CUSTOM_ACCESSION%%.*}"
      local base f
      for base in "\${CUSTOM_ACCESSION}.fasta" "\${stem}.fasta" "\${CUSTOM_ACCESSION}.fna" "\${stem}.fna"; do
        f="\${CUSTOM_STAGING}/\${base}"
        if [ -f "\$f" ] && [ -f "\${DB_SUBDIR}/\${base}" ]; then
          rm -f "\$f"
        elif [ -f "\$f" ]; then
          mv "\$f" "\${DB_SUBDIR}/"
        fi
      done
      for f in "\${CUSTOM_STAGING}/\${stem}.fasta.mmi" "\${CUSTOM_STAGING}/\${CUSTOM_ACCESSION}.fasta.mmi"; do
        if [ -f "\$f" ] && [ -f "\${DB_SUBDIR}/\$(basename "\$f")" ]; then
          rm -f "\$f"
        elif [ -f "\$f" ]; then
          mv "\$f" "\${DB_SUBDIR}/"
        fi
      done
      if [ -d "\${CUSTOM_STAGING}/taxonomy" ] && [ -d "\${DB_SUBDIR}/taxonomy" ]; then
        rm -rf "\${CUSTOM_STAGING}/taxonomy"
      fi
    }

    finalize_custom_layout () {
      organize_custom_from_staging
      cleanup_custom_staging_root
    }

    find_custom_fasta () {
      finalize_custom_layout
      find_primary_fasta "\$DB_SUBDIR"
    }

    find_primary_fasta () {
      local root="\$1"
      [ -d "\$root" ] || return 1
      if [ "\$DB_KIND" = "rvdb" ]; then
        if [ -n "\$ACCESSIONS" ]; then
          local with_acc
          with_acc=\$(find "\$root" -maxdepth 1 -type f -name 'RVDB*_complete_with_accessions.fasta' -size +\${MIN_BYTES}c 2>/dev/null | sort | tail -n 1)
          if [ -n "\$with_acc" ]; then
            printf '%s\\n' "\$with_acc"
            return
          fi
        fi
        find "\$root" -maxdepth 1 -type f -name 'RVDB*_complete.fasta' ! -name '*_with_accessions.fasta' -size +\${MIN_BYTES}c 2>/dev/null | sort | tail -n 1
        return
      fi
      if [ "\$DB_KIND" = "refseq" ]; then
        local f="\$root/\$FASTA_REL"
        if [ -s "\$f" ] && [ "\$(stat -c%s "\$f" 2>/dev/null || stat -f%z "\$f")" -ge "\$MIN_BYTES" ]; then
          printf '%s\\n' "\$f"
        fi
        return
      fi
      if [ "\$DB_KIND" = "custom" ]; then
        local acc="\$CUSTOM_ACCESSION"
        local stem="\${acc%%.*}"
        local name f size
        for name in "\${acc}.fasta" "\${acc}.fna" "\${acc}.fa" "\${stem}.fasta" "\${stem}.fna" "\${stem}.fa"; do
          f="\$root/\$name"
          if [ -s "\$f" ]; then
            size="\$(stat -c%s "\$f" 2>/dev/null || stat -f%z "\$f")"
            if [ "\$size" -ge "\$MIN_BYTES" ]; then
              printf '%s\\n' "\$f"
              return
            fi
          fi
        done
        return 1
      fi
      find "\$root" -type f \\( -name '*.fasta' -o -name '*.fna' -o -name '*.fa' \\) -size +\${MIN_BYTES}c 2>/dev/null | sort | tail -n 1
    }

    # Virasign stores NCBI dumps + SQLite under <db>/taxonomy/ (or legacy taxonomy_cache/).
    # Never wipe these during re-prepare: nucl_gb.accession2taxid.gz is multi-GB and
    # classification will re-download it if the tree is removed but SQLite is missing.
    taxonomy_ready () {
      local root="\$1"
      local db
      for db in \\
        "\$root/taxonomy/accession_to_organism_database.db" \\
        "\$root/taxonomy_cache/accession_to_organism_database.db"
      do
        if [ -s "\$db" ]; then
          return 0
        fi
      done
      return 1
    }

    # Drop FASTA/index/metadata for a fresh prepare, but keep taxonomy/ dumps + SQLite.
    clear_db_artifacts_keep_taxonomy () {
      local root="\$1"
      [ -d "\$root" ] || return 0
      local f
      for f in "\$root"/*; do
        [ -e "\$f" ] || continue
        case "\${f##*/}" in
          taxonomy|taxonomy_cache) continue ;;
        esac
        rm -rf "\$f"
      done
    }

    marker_matches () {
      local m=""
      if [ -f "\$MARKER" ]; then
        m="\$MARKER"
      elif [ -n "\$LEGACY_MARKER" ] && [ -f "\$LEGACY_MARKER" ]; then
        m="\$LEGACY_MARKER"
      else
        return 1
      fi
      grep -qxF "fingerprint=\$FP_HASH" "\$m" || return 1
      local recorded="\$(grep -E '^fasta_path=' "\$m" | head -n 1 | cut -d= -f2-)"
      [ -n "\$recorded" ] || return 1
      [ -s "\$recorded" ] || return 1
      local size="\$(stat -c%s "\$recorded" 2>/dev/null || stat -f%z "\$recorded")"
      [ "\$size" -ge "\$MIN_BYTES" ] || return 1
      return 0
    }

    write_marker () {
      local fasta="\$1"
      local size="\$(stat -c%s "\$fasta" 2>/dev/null || stat -f%z "\$fasta")"
      mkdir -p "\$(dirname "\$MARKER")"
      cat > "\$MARKER" <<MARKER_EOF
fingerprint=\$FP_HASH
fasta_path=\$fasta
fasta_bytes=\$size
completed_at=\$(date -u +%Y-%m-%dT%H:%M:%SZ)
MARKER_EOF
    }

    recover_or_prepare () {
      cleanup_wrong_custom_roots
      local fasta
      if [ "\$DB_KIND" = "custom" ]; then
        fasta="\$(find_custom_fasta || true)"
      else
        fasta="\$(find_primary_fasta "\$DB_SUBDIR" || true)"
      fi

      if marker_matches && taxonomy_ready "\$DB_SUBDIR"; then
        echo "Virasign database ready under \${DB_DIR} (${effectiveDbArg}); marker + taxonomy valid."
        return 0
      fi

      if marker_matches && ! taxonomy_ready "\$DB_SUBDIR"; then
        echo "Virasign FASTA marker valid but taxonomy SQLite missing under \${DB_SUBDIR}; completing via prepare-db (keeping any NCBI dumps)."
      elif [ -f "\$MARKER" ]; then
        echo "Virasign database marker is stale or incomplete; clearing FASTA/index (preserving taxonomy/) and re-preparing..."
        rm -f "\$MARKER"
        clear_db_artifacts_keep_taxonomy "\$DB_SUBDIR"
        fasta=""
      elif [ -n "\$fasta" ] && taxonomy_ready "\$DB_SUBDIR"; then
        echo "Virasign database FASTA + taxonomy present without marker; recording completion marker."
        finalize_custom_layout
        fasta="\$(find_primary_fasta "\$DB_SUBDIR" || true)"
        write_marker "\$fasta"
        return 0
      elif [ -n "\$fasta" ]; then
        echo "Virasign FASTA present but taxonomy incomplete under \${DB_SUBDIR}; running prepare-db to finish taxonomy (keeping FASTA)."
      else
        echo "Virasign database missing or incomplete under \${DB_SUBDIR}; clearing partial FASTA/index (preserving taxonomy/)..."
        clear_db_artifacts_keep_taxonomy "\$DB_SUBDIR"
        rm -f "\$MARKER" || true
      fi

      # Named DBs write directly into DB_SUBDIR. Custom stages under Custom/ then we move.
      if [ "\$DB_KIND" != "custom" ]; then
        mkdir -p "\$DB_SUBDIR"
      fi
      ${cmd}

      if [ "\$DB_KIND" = "custom" ]; then
        finalize_custom_layout
        fasta="\$(find_primary_fasta "\$DB_SUBDIR" || true)"
      else
        fasta="\$(find_primary_fasta "\$DB_SUBDIR" || true)"
      fi
      if [ -z "\$fasta" ]; then
        echo "ERROR: virasign --prepare-db finished but no valid database FASTA was found under \${DB_SUBDIR}." >&2
        echo "ERROR: leaving \${DB_SUBDIR} in place (including taxonomy/) for inspection; not wiping." >&2
        rm -f "\$MARKER" || true
        exit 1
      fi
      if [ "\$DB_KIND" = "custom" ]; then
        fasta="\$(find_primary_fasta "\$DB_SUBDIR" || true)"
      fi
      if ! taxonomy_ready "\$DB_SUBDIR"; then
        echo "WARNING: prepare-db finished but taxonomy SQLite still missing under \${DB_SUBDIR}/taxonomy/." >&2
        echo "WARNING: classification may re-download nucl_gb.accession2taxid.gz." >&2
      fi
      write_marker "\$fasta"
      echo "Virasign database prepared successfully."
    }

    recover_or_prepare

    echo "ready" > db_ready.txt

    VIRASIGN_VERSION=\$(virasign --version 2>&1 | head -n1 || echo 'unknown')
    cat > versions.yml <<END_VERSIONS
"${task.process}":
    virasign: "\${VIRASIGN_VERSION}"
END_VERSIONS
    """
}
