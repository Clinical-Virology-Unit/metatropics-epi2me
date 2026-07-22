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

    static String apply(Map params, String repoRoot, def log) {
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
            return
        }

        switch (source.toUpperCase()) {
            case 'RVDB':
            case 'REFSEQ':
                break
            case 'CUSTOM':
                if (!params.virasign_accessions?.toString()?.trim()) {
                    log.error "virasign_accessions is required when virasign_db_source is Custom"
                    System.exit(1)
                }
                break
            default:
                log.error "Unknown virasign_db_source '${source}' (expected RVDB, RefSeq, or Custom)"
                System.exit(1)
        }
    }

    static String resolveReadsPath(String reads, String inputMode) {
        def dir = new File(reads)
        if (!dir.exists()) {
            throw new IllegalArgumentException("reads path not found: ${reads}")
        }
        if (!dir.isDirectory()) {
            throw new IllegalArgumentException("reads must be a directory: ${reads}")
        }

        if (inputMode == 'fastq_pass') {
            def fastqPass = new File(dir, 'fastq_pass')
            if (fastqPass.isDirectory()) {
                return fastqPass.absolutePath
            }
        }

        if (inputMode == 'pod5') {
            def pod5Pass = new File(dir, 'pod5_pass')
            if (pod5Pass.isDirectory()) {
                return pod5Pass.absolutePath
            }
        }

        return dir.absolutePath
    }

    private static void generateSamplesheet(String inputMode, String readsPath, File out, String repoRoot, def log) {
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
