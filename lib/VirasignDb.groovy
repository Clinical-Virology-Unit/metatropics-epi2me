//
// Virasign database layout and completion checks for prepare-db.
//

import java.security.MessageDigest

class VirasignDb {

    static String databaseDir(Map params, String projectDir) {
        params.virasign_db_dir ?: "${projectDir}/Databases"
    }

    /** Directory passed to virasign `--db-dir` (per-accession root for Custom). */
    static String virasignDbDir(Map params, String projectDir) {
        def layout = dbLayout(params, projectDir)
        layout.virasign_db_dir ?: databaseDir(params, projectDir)
    }

    static String effectiveDatabase(Map params) {
        def source = params.virasign_db_source?.toString()?.trim()
        if (source) {
            switch (source.toUpperCase()) {
                case 'RVDB':
                    return 'RVDB'
                case 'REFSEQ':
                    return 'RefSeq'
                case 'CUSTOM':
                    def acc = params.virasign_accessions?.toString()?.trim()
                    if (acc) {
                        return acc.split(',')[0].trim()
                    }
                    break
            }
        }
        return params.virasign_database?.toString()?.trim() ?: 'RVDB'
    }

    /** Pass `-a` to virasign only when filtering a bundled DB (RVDB/RefSeq), not for Custom-only accessions. */
    static boolean passAccessionsArg(Map params) {
        def source = params.virasign_db_source?.toString()?.trim()?.toUpperCase()
        if (source == 'CUSTOM') {
            return false
        }
        return params.virasign_accessions?.toString()?.trim() as boolean
    }

    static String dbLabel(Map params) {
        effectiveDatabase(params).replaceAll(/[^A-Za-z0-9._-]+/, '_')
    }

    /** True when -d is an NCBI accession (Custom), not bundled RVDB/RefSeq. */
    static boolean isCustomAccessionDb(Map params) {
        def lower = effectiveDatabase(params).toLowerCase()
        return lower != 'rvdb' && lower != 'refseq'
    }

    static Map dbLayout(Map params, String projectDir) {
        def dbDir = databaseDir(params, projectDir)
        def db = effectiveDatabase(params)
        def lower = db.toLowerCase()

        if (lower == 'rvdb') {
            return [
                subdir    : "${dbDir}/RVDB",
                marker    : "${dbDir}/RVDB/.metatropics_prepare_db.done",
                min_bytes : 10_000_000L,
                kind      : 'rvdb',
            ]
        }
        if (lower == 'refseq') {
            return [
                subdir    : "${dbDir}/RefSeq",
                marker    : "${dbDir}/RefSeq/.metatropics_prepare_db.done",
                fasta_rel : 'viral_refseq_complete.fna',
                min_bytes : 1_000_000L,
                kind      : 'refseq',
            ]
        }

        def safe = db.replaceAll(/[^A-Za-z0-9._-]+/, '_')
        def customRoot = "${dbDir}/Custom"
        def accDir = "${customRoot}/${safe}"
        // virasign --prepare-db always uses --db-dir <Databases> and stages flat files under
        // Databases/Custom/*.fasta; we then move them into Databases/Custom/<accession>/.
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
            "database=${effectiveDatabase(params)}",
            "rvdb_version=${params.virasign_rvdb_version ?: ''}",
            "accessions=${params.virasign_accessions?.toString()?.trim() ?: ''}",
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
