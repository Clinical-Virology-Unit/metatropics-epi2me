//
// Virasign database layout and completion checks for prepare-db.
//

import java.security.MessageDigest

class VirasignDb {

    static String databaseDir(Map params, String projectDir) {
        params.virasign_db_dir ?: "${projectDir}/Databases"
    }

    /** Directory passed to virasign `--db-dir` (shared Databases root for all kinds). */
    static String virasignDbDir(Map params, String projectDir) {
        def layout = dbLayout(params, projectDir)
        layout.virasign_db_dir ?: databaseDir(params, projectDir)
    }

    /** Normalised EPI2ME/CLI source: RVDB | REFSEQ | CUSTOM (or null). */
    static String dbSource(Map params) {
        def source = params.virasign_db_source?.toString()?.trim()?.toUpperCase()
        if (source in ['RVDB', 'REFSEQ', 'CUSTOM']) {
            return source
        }
        // Accessions without an explicit source → Custom (never silently fall back to RVDB+-a).
        if (accessionList(params)) {
            return 'CUSTOM'
        }
        def named = params.virasign_database?.toString()?.trim()?.toLowerCase()
        if (named == 'refseq') {
            return 'REFSEQ'
        }
        if (named == 'rvdb' || !named) {
            return 'RVDB'
        }
        // Named value is an accession / custom label.
        return 'CUSTOM'
    }

    static List<String> accessionList(Map params) {
        def raw = params.virasign_accessions?.toString()?.trim()
        if (!raw) {
            return []
        }
        return raw.split(',').collect { it.trim() }.findAll { it }
    }

    /**
     * Value for virasign `-d`:
     * - RVDB / RefSeq named DB
     * - first Custom accession (additional accessions go via `-a`)
     */
    static String effectiveDatabase(Map params) {
        switch (dbSource(params)) {
            case 'RVDB':
                return 'RVDB'
            case 'REFSEQ':
                return 'RefSeq'
            case 'CUSTOM':
                def accs = accessionList(params)
                if (accs) {
                    return accs[0]
                }
                def named = params.virasign_database?.toString()?.trim()
                if (named && named.toLowerCase() != 'rvdb' && named.toLowerCase() != 'refseq') {
                    return named
                }
                throw new IllegalArgumentException(
                    "Custom Virasign database requires virasign_accessions (comma-separated NCBI accessions)."
                )
            default:
                return params.virasign_database?.toString()?.trim() ?: 'RVDB'
        }
    }

    /**
     * Extra accessions for virasign `-a`:
     * - Custom: all accessions after the first (first is `-d`)
     * - RVDB/RefSeq: all listed accessions merged into that named DB
     * Never use `-a` alone with default RVDB when the user asked for Custom.
     */
    static String additionalAccessionsArg(Map params) {
        def accs = accessionList(params)
        if (!accs) {
            return ''
        }
        if (dbSource(params) == 'CUSTOM') {
            return accs.size() > 1 ? accs[1..-1].join(',') : ''
        }
        return accs.join(',')
    }

    static boolean passAccessionsArg(Map params) {
        additionalAccessionsArg(params) as boolean
    }

    /** Only pass --rvdb-version when preparing/using RVDB. */
    static boolean passRvdbVersionArg(Map params) {
        dbSource(params) == 'RVDB' && params.virasign_rvdb_version != null
    }

    static String dbLabel(Map params) {
        if (dbSource(params) == 'CUSTOM') {
            def accs = accessionList(params)
            if (accs) {
                return accs.collect { it.replaceAll(/[^A-Za-z0-9._-]+/, '_') }.join('_')
            }
        }
        effectiveDatabase(params).replaceAll(/[^A-Za-z0-9._-]+/, '_')
    }

    /** True when -d is an NCBI accession (Custom), not bundled RVDB/RefSeq. */
    static boolean isCustomAccessionDb(Map params) {
        dbSource(params) == 'CUSTOM'
    }

    static Map dbLayout(Map params, String projectDir) {
        def dbDir = databaseDir(params, projectDir)
        def source = dbSource(params)

        if (source == 'RVDB') {
            return [
                subdir    : "${dbDir}/RVDB",
                marker    : "${dbDir}/RVDB/.metatropics_prepare_db.done",
                min_bytes : 10_000_000L,
                kind      : 'rvdb',
            ]
        }
        if (source == 'REFSEQ') {
            return [
                subdir    : "${dbDir}/RefSeq",
                marker    : "${dbDir}/RefSeq/.metatropics_prepare_db.done",
                fasta_rel : 'viral_refseq_complete.fna',
                min_bytes : 1_000_000L,
                kind      : 'refseq',
            ]
        }

        def db = effectiveDatabase(params)
        def safe = db.replaceAll(/[^A-Za-z0-9._-]+/, '_')
        def customRoot = "${dbDir}/Custom"
        def accDir = "${customRoot}/${safe}"
        // virasign --prepare-db stages flat files under Databases/Custom/*.fasta;
        // we then move them into Databases/Custom/<accession>/.
        return [
            subdir          : accDir,
            custom_staging  : customRoot,
            virasign_db_dir : dbDir,
            marker          : "${accDir}/.metatropics_prepare_db.done",
            legacy_marker   : "${dbDir}/.metatropics_prepare_db_${safe}.done",
            min_bytes       : 1000L,
            kind            : 'custom',
            accession       : safe,
        ]
    }

    static String markerFingerprint(Map params) {
        def lines = [
            "source=${dbSource(params)}",
            "database=${effectiveDatabase(params)}",
            "rvdb_version=${dbSource(params) == 'RVDB' ? (params.virasign_rvdb_version ?: '') : ''}",
            "accessions=${accessionList(params).join(',')}",
            "clustering=${params.virasign_enable_clustering == true}",
            "cluster_identity=${params.virasign_cluster_identity ?: ''}",
            "max_ambiguous_fraction=${params.virasign_max_ambiguous_fraction ?: ''}",
        ]
        return lines.join('\n')
    }

    static String markerFingerprintHash(Map params) {
        MessageDigest.getInstance('SHA-256')
            .digest(markerFingerprint(params).bytes)
            .encodeHex()
            .toString()
    }

    /** Groovy-side quick check (prepare_db shell script is authoritative on resume). */
    static boolean isComplete(Map params, String projectDir) {
        def layout = dbLayout(params, projectDir)
        def marker = new File(layout.marker as String)
        if (!marker.isFile()) {
            return false
        }
        def text = marker.getText('UTF-8')
        if (!text.contains("fingerprint=${markerFingerprintHash(params)}")) {
            return false
        }
        def fastaPath = text.readLines()
            .find { it.startsWith('fasta_path=') }
            ?.substring('fasta_path='.length())
        if (!fastaPath) {
            return false
        }
        def fasta = new File(fastaPath)
        if (!fasta.isFile()) {
            return false
        }
        return fasta.length() >= (layout.min_bytes as long)
    }
}
