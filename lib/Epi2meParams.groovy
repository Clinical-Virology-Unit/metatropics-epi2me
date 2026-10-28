//
// Map EPI2ME Desktop parameters to Metatropics pipeline parameters.
//

class Epi2meParams {

    private static final List<String> FASTQ_SUFFIXES = ['.fastq.gz', '.fq.gz', '.fastq', '.fq']

    /** True when launched from EPI2ME Desktop (--reads set). */
    static boolean isEpi2me(Map params) {
        params.reads?.toString()?.trim() as boolean
    }

    static boolean publishReads(Map params) {
        !isEpi2me(params) || params.epi2me_publish_reads
    }

    static boolean publishBam(Map params) {
        !isEpi2me(params) || params.epi2me_publish_bam
    }

    /**
     * Ensure the resolved Databases/ root exists and log it when using a custom EPI2ME location
     * (or an explicit --virasign_db_dir). Does not mutate params (Nextflow ignores reassignment).
     */
    static void applyDbLocation(Map params, String projectDir, def log) {
        def dbDir = new File(VirasignDb.databaseDir(params, projectDir))
        def custom = VirasignDb.specifyOwnDbLocation(params) || params.virasign_db_dir?.toString()?.trim()
        if (custom) {
            dbDir.mkdirs()
            log.info "EPI2ME Databases location: ${dbDir.absolutePath}"
        }
    }

    // EPI2ME checkbox params (booleans render reliably; array multi-select often does not).
    private static final Map BLIND_CHECKBOXES = [
        epi2me_blind_hiv : 'HIV',
        epi2me_blind_hep : 'HEP',
        epi2me_blind_htlv: 'HTLV',
        epi2me_blind_ebv : 'EBV',
        epi2me_blind_cmv : 'CMV',
        epi2me_blind_hpv : 'HPV',
    ]

    /**
     * Virasign -b argument from EPI2ME checkboxes and/or CLI --virasign_blind / epi2me_blind_species.
     * Does not mutate params (Nextflow may ignore reassignment of config keys).
     */
    static String blindSpeciesArg(Map params) {
        def codes = []
        BLIND_CHECKBOXES.each { paramName, abbrev ->
            if (isTruthy(params[paramName])) {
                codes << abbrev
            }
        }
        // Free-text official taxonomy names from EPI2ME (comma-separated).
        collectBlindTokens(params.epi2me_blind_custom, codes)
        collectBlindTokens(params.epi2me_blind_species, codes)
        // Legacy/CLI: species abbreviations (not a file path).
        def legacy = params.virasign_blind?.toString()?.trim()
        if (legacy && !looksLikeFilesystemPath(legacy)) {
            collectBlindTokens(legacy, codes)
        }
        return codes.unique(false).join(',')
    }

    static boolean isTruthy(Object flag) {
        if (flag == null) {
            return false
        }
        if (flag instanceof Boolean) {
            return flag
        }
        return ['true', '1', 'yes', 'y', 'on'].contains(flag.toString().trim().toLowerCase())
    }

    // EPI2ME shows "HIV - Human immunodeficiency virus (...)"; Virasign -b needs HIV/HEP/...
    private static final List<String> BLIND_ABBREVS = ['HIV', 'HEP', 'HTLV', 'EBV', 'CMV', 'HPV']

    private static void collectBlindTokens(Object value, List codes) {
        if (value == null) {
            return
        }
        // EPI2ME multi-select: each list item is one labeled enum (may contain commas in the name).
        if (value instanceof Collection) {
            value.each { item ->
                def code = normalizeBlindAbbreviation(item?.toString())
                if (code) {
                    codes << code
                }
            }
            return
        }
        def raw = value.toString().trim()
        if (!raw || raw.equalsIgnoreCase('none') || raw == '[]') {
            return
        }
        raw = raw.replaceAll(/^\[|\]$/, '').trim()
        // Labeled single value ("HEP - All hepatitis viruses (HAV-HEV, incl. HBV/HCV)") — do not split on commas.
        if (raw.contains(' - ') || raw.contains(' – ') || raw.contains(' — ')) {
            def code = normalizeBlindAbbreviation(raw)
            if (code) {
                codes << code
            }
            return
        }
        // CLI: comma-separated short codes (HIV,HEP,HTLV)
        raw.split(',').each { tok ->
            def code = normalizeBlindAbbreviation(tok?.toString()?.trim())
            if (code) {
                codes << code
            }
        }
    }

    /**
     * Map EPI2ME labeled enum / short code / full species name → Virasign abbreviation.
     */
    static String normalizeBlindAbbreviation(String raw) {
        if (!raw) {
            return null
        }
        def t = raw.trim()
        if (!t || t.equalsIgnoreCase('none')) {
            return null
        }
        // "HIV - Human immunodeficiency virus (...)" or "HIV — ..."
        def head = t.split(/\s*[-–—]\s*/, 2)[0].trim()
        def upperHead = head.toUpperCase()
        if (BLIND_ABBREVS.contains(upperHead)) {
            return upperHead
        }
        // Bare abbreviation
        def upper = t.toUpperCase()
        if (BLIND_ABBREVS.contains(upper)) {
            return upper
        }
        // Leading token before space/paren: "HIV (Human ...)"
        def m = (t =~ /^([A-Za-z]+)\b/)
        if (m.find()) {
            def tok = m.group(1).toUpperCase()
            if (BLIND_ABBREVS.contains(tok)) {
                return tok
            }
        }
        // Pass through unrecognized values (full species names still valid for Virasign -b)
        return t
    }

    static boolean looksLikeFilesystemPath(String value) {
        if (!value) {
            return false
        }
        if (value.contains('/') || value.contains('\\')) {
            return true
        }
        def f = new File(value)
        return f.exists()
    }

    static void logBlinding(Map params, def log) {
        def blind = blindSpeciesArg(params)
        if (blind) {
            log.info "Blinding incidental findings: ${blind}"
        }
    }

    static String apply(Map params, String repoRoot, def log) {
        applyDbLocation(params, repoRoot, log)

        if (!params.reads?.toString()?.trim()) {
            return null
        }

        def inputMode = params.input_mode?.toString()?.trim()
        if (!inputMode) {
            log.error "EPI2ME mode requires --input_mode (demultiplexed_fastq | fastq_pass | pod5)"
            System.exit(1)
        }

        applyVirasignDb(params, log)
        applyHostSelections(params, log)

        def readsPath = resolveReadsPath(params.reads.toString().trim(), inputMode)
        def workDir = new File("${repoRoot}/.epi2me_work")
        workDir.mkdirs()
        def sheetFile = new File(workDir, "samplesheet_epi2me.csv")

        if (params.sample_sheet?.toString()?.trim()) {
            convertEpi2meSampleSheet(
                params.sample_sheet.toString().trim(),
                sheetFile,
                params.kit_name?.toString()?.trim(),
                repoRoot,
                log
            )
        } else {
            generateSamplesheet(inputMode, readsPath, sheetFile, repoRoot, log)
        }

        def sheetPath = sheetFile.absolutePath

        switch (inputMode) {
            case 'demultiplexed_fastq':
                params.basecall = false
                params.input_dir = null
                break
            case 'fastq_pass':
                params.basecall = false
                params.input_dir = readsPath
                break
            case 'pod5':
                params.basecall = true
                params.input_dir = readsPath
                break
            default:
                log.error "Unknown input_mode '${inputMode}' (expected demultiplexed_fastq, fastq_pass, or pod5)"
                System.exit(1)
        }

        log.info "EPI2ME ingress: mode=${inputMode}, reads=${readsPath}, samplesheet=${sheetPath}, publish_reads=${publishReads(params)}, publish_bam=${publishBam(params)}"
        return sheetPath
    }

    private static final List<String> HOST_ENUM = [
        'human', 'pan', 'gorilla', 'orangutan', 'macaque',
        'aedes', 'anopheles', 'culex', 'bat', 'rat', 'dog', 'cat',
        'camel', 'goat', 'pig', 'cow', 'mouse', 'chicken',
    ]

    private static void applyHostSelections(Map params, def log) {
        def selected = []

        def addHost = { value ->
            if (!value) return
            if (value instanceof List) {
                value.each { addHost(it) }
                return
            }
            def key = value.toString().trim().toLowerCase()
            if (key && key != 'none' && HOST_ENUM.contains(key)) {
                selected << key
            }
        }

        addHost(params.Host)
        addHost(params.Host_additional)

        selected = selected.unique()
        if (selected) {
            params.Host = selected.size() == 1 ? selected[0] : selected
            log.info "EPI2ME host depletion: ${selected.join(', ')}"
        } else {
            params.Host = null
        }
    }

    private static void applyVirasignDb(Map params, def log) {
        def source = params.virasign_db_source?.toString()?.trim()
        if (!source) {
            // Keep legacy CLI behaviour when only virasign_database is set.
            return
        }

        switch (source.toUpperCase()) {
            case 'RVDB':
                params.virasign_database = 'RVDB'
                // Avoid merging leftover Custom accessions into RVDB via -a.
                params.virasign_accessions = null
                break
            case 'REFSEQ':
                params.virasign_database = 'RefSeq'
                // Do not keep leftover Custom accessions that would be merged into RefSeq via -a.
                params.virasign_accessions = null
                break
            case 'CUSTOM':
                if (!params.virasign_accessions?.toString()?.trim()) {
                    log.error "virasign_accessions is required when virasign_db_source is Custom"
                    System.exit(1)
                }
                // Pin named DB away from the default RVDB so nothing falls back to downloading it.
                params.virasign_database = params.virasign_accessions.toString().trim().split(',')[0].trim()
                break
            default:
                log.error "Unknown virasign_db_source '${source}' (expected RVDB, RefSeq, or Custom)"
                System.exit(1)
        }
    }

    static String resolveReadsPath(String reads, String inputMode) {
        def path = new File(reads)
        if (!path.exists()) {
            throw new IllegalArgumentException("reads path not found: ${reads}")
        }

        // demultiplexed_fastq: allow a single FASTQ file or a directory of FASTQs/barcode folders.
        if (path.isFile()) {
            if (inputMode != 'demultiplexed_fastq') {
                throw new IllegalArgumentException(
                    "reads must be a directory for input_mode=${inputMode} (got a file): ${reads}"
                )
            }
            if (!isFastq(path.name)) {
                throw new IllegalArgumentException(
                    "reads file must be a FASTQ (.fastq/.fq[.gz]): ${reads}"
                )
            }
            return path.absolutePath
        }

        if (!path.isDirectory()) {
            throw new IllegalArgumentException("reads must be a directory or FASTQ file: ${reads}")
        }

        if (inputMode == 'fastq_pass') {
            def fastqPass = new File(path, 'fastq_pass')
            if (fastqPass.isDirectory()) {
                return fastqPass.absolutePath
            }
        }

        if (inputMode == 'pod5') {
            def pod5Pass = new File(path, 'pod5_pass')
            if (pod5Pass.isDirectory()) {
                return pod5Pass.absolutePath
            }
        }

        return path.absolutePath
    }

    private static void generateSamplesheet(String inputMode, String readsPath, File out, String repoRoot, def log) {
        def readsFile = new File(readsPath)
        if (inputMode == 'demultiplexed_fastq' && readsFile.isFile()) {
            writeSingleFastqSheet(readsFile, out, log)
            return
        }

        if (inputMode == 'demultiplexed_fastq') {
            if (writeBarcodeFolderSheet(readsPath, out, log)) {
                return
            }
        }

        def pyMode = (inputMode == 'demultiplexed_fastq') ? 'fastq' : 'pod5'
        def assetsDir = new File("${repoRoot}/assets")
        def cmd = [
            'python3', '-m', 'metatropics_samplesheet', pyMode,
            '-i', readsPath,
            '-o', out.absolutePath,
        ]
        def pb = new ProcessBuilder(cmd)
        pb.directory(assetsDir)
        pb.environment().put('PYTHONPATH', assetsDir.absolutePath)
        pb.redirectErrorStream(true)
        def proc = pb.start()
        def output = proc.inputStream.text
        proc.waitFor()
        if (proc.exitValue() != 0) {
            log.error "Samplesheet generation failed:\n${output}"
            System.exit(1)
        }
        if (output?.trim()) {
            log.info output.trim()
        }
    }

    private static void writeSingleFastqSheet(File fq, File out, def log) {
        def sample = fq.name
        for (String suf : FASTQ_SUFFIXES) {
            def lower = sample.toLowerCase()
            if (lower.endsWith(suf)) {
                sample = sample.substring(0, sample.length() - suf.length())
                break
            }
        }
        if (!sample) {
            sample = 'sample'
        }
        writeCsv(out, [[sample, fq.absolutePath]])
        log.info "Wrote 1 sample from single FASTQ to ${out.absolutePath}"
    }

    private static boolean writeBarcodeFolderSheet(String readsPath, File out, def log) {
        def dir = new File(readsPath)
        def subdirs = dir.listFiles()?.findAll { it.isDirectory() && it.name ==~ /(?i)barcode\d+/ }?.sort { it.name }
        if (!subdirs) {
            return false
        }

        def rows = []
        subdirs.each { sub ->
            def fastq = findFirstFastq(sub)
            if (!fastq) {
                log.warn "Skipping ${sub.name}: no FASTQ found"
                return
            }
            rows << [sub.name, fastq.absolutePath]
        }

        if (!rows) {
            return false
        }

        writeCsv(out, rows)
        log.info "Wrote ${rows.size()} barcode folder(s) to ${out.absolutePath}"
        return true
    }

    private static File findFirstFastq(File directory) {
        def files = directory.listFiles()?.findAll { it.isFile() && isFastq(it.name) }?.sort { it.name }
        return files ? files[0] : null
    }

    private static boolean isFastq(String name) {
        def lower = name.toLowerCase()
        return FASTQ_SUFFIXES.any { lower.endsWith(it) }
    }

    private static void convertEpi2meSampleSheet(String path, File out, String kitName, String repoRoot, def log) {
        def assetsDir = new File("${repoRoot}/assets")
        def cmd = [
            'python3', '-m', 'metatropics_samplesheet', 'epi2me',
            '-i', path,
            '-o', out.absolutePath,
        ]
        if (kitName) {
            cmd.addAll(['--kit', kitName])
        }
        def pb = new ProcessBuilder(cmd)
        pb.directory(assetsDir)
        pb.environment().put('PYTHONPATH', assetsDir.absolutePath)
        pb.redirectErrorStream(true)
        def proc = pb.start()
        def output = proc.inputStream.text
        proc.waitFor()
        if (proc.exitValue() != 0) {
            log.error "EPI2ME sample sheet conversion failed:\n${output}"
            System.exit(1)
        }
        if (output?.trim()) {
            log.info output.trim()
        }
    }

    private static void writeCsv(File out, List<List<String>> rows) {
        out.parentFile.mkdirs()
        out.withWriter { w ->
            w.writeLine('sample,barcode')
            rows.each { row ->
                w.writeLine("${row[0]},${row[1]}")
            }
        }
    }
}
