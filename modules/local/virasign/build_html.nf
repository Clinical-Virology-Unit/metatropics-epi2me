process VIRASIGN_SUMMARY {
    tag "Metatropics summary report"
    label 'process_medium'

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'docker://daanjansen94/virasign:v0.1.3':
        'daanjansen94/virasign:v0.1.3' }"

    // Bind outdir and read results via params.
    def outAbs = file(params.outdir ?: params.out_dir).toAbsolutePath().toString()
    def pipelineRoot = new File("${projectDir}").parentFile.absolutePath
    def db_dir = params.virasign_db_dir ?: "${pipelineRoot}/Databases"
    def dbAbs = file(db_dir).toAbsolutePath().toString()

    // Ensure any control/blind files are visible in-container.
    def extraBindDirs = []
    def addBindDir = { String p ->
        if (!p) return
        def fp = file(p)
        def d = fp.isDirectory() ? fp : fp.parent
        if (d != null) extraBindDirs << d.toAbsolutePath().toString()
    }
    def zc = params.virasign_zscore_controls?.toString()?.trim()
    if (zc) {
        // Bind only real paths; sample IDs (e.g. H20_1,BG_1) need no bind.
        zc.split(',').collect { it.trim() }.findAll { it }.each { tok ->
            def fp = file(tok)
            if (fp.exists()) addBindDir(tok)
        }
    }
    addBindDir(params.virasign_blind?.toString()?.trim())
    // Samplesheet so the summary can include input samples that never reached Virasign
    // (e.g. empty after host depletion, or dropped by an optional upstream output).
    addBindDir((params.input ?: params.epi2me_samplesheet ?: params.sample_sheet)?.toString()?.trim())
    extraBindDirs = extraBindDirs.unique()

    if (workflow.containerEngine == 'docker' || workflow.containerEngine == 'podman') {
        def extra = extraBindDirs.collect { " -v ${it}:${it}" }.join('')
        containerOptions "-v ${outAbs}:${outAbs} -v ${dbAbs}:${dbAbs}${extra}"
    }
    if (workflow.containerEngine == 'singularity' || workflow.containerEngine == 'apptainer') {
        def extra = extraBindDirs.collect { " --bind ${it}:${it}" }.join('')
        containerOptions "--bind ${outAbs}:${outAbs} --bind ${dbAbs}:${dbAbs}${extra}"
    }

    input:
    val _consensus_count
    val _virasign_results_count
    // Barrier / optional consensus FASTAs. When zero viral hits, Clair3/consensus never run —
    // the workflow passes assets/NO_CONSENSUS.placeholder instead of an empty path list.
    path consensus_fastas, stageAs: 'consensus/*'

    output:
    path "Metatropics_Summary_*.html", emit: html
    path "Metatropics_Summary_*.csv",  emit: csv
    path "versions.yml",           emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    // Nextflow 23.04: avoid `def x = fn(params)` after process directives already touch params.
    rawDbArg = VirasignDb.effectiveDatabase(params)
    effectiveDbArg = rawDbArg ?: 'RefSeq'
    virasignDbLabel = VirasignDb.dbLabel(params)
    outroot = file("${params.outdir ?: params.out_dir}/Classification/virasign/${virasignDbLabel}").toAbsolutePath().toString()
    outHtml = "Metatropics_Summary_${virasignDbLabel}.html"
    outCsv  = "Metatropics_Summary_${virasignDbLabel}.csv"
    zscore = params.virasign_zscore ?: 'true'
    zscore_controls = params.virasign_zscore_controls?.toString()?.trim()
    zscore_controls_safe = zscore_controls ?: ''
    virasign_blind_safe = params.virasign_blind?.toString()?.trim() ?: ''
    zscore_json = groovy.json.JsonOutput.toJson(zscore?.toString()?.trim() ?: 'false')
    zscore_controls_json = groovy.json.JsonOutput.toJson(zscore_controls_safe)
    virasign_blind_json = groovy.json.JsonOutput.toJson(virasign_blind_safe)
    samplesheet_json = groovy.json.JsonOutput.toJson((params.input ?: params.epi2me_samplesheet ?: params.sample_sheet)?.toString()?.trim() ?: '')
    virasign_db_label_json = groovy.json.JsonOutput.toJson(virasignDbLabel)
    quality = params.quality?.toString() ?: 'NA'
    depth = params.depth?.toString() ?: 'NA'
    agreement = params.agreement?.toString() ?: 'NA'
    def opt = []
    def add = { c, f -> if (c) opt << f }
    add(true, "--db-dir '${dbAbs}'")
    add(!!zscore, "--zscore ${zscore}")
    add(zscore_controls, "--zscore-controls '${zscore_controls}'")
    add(params.virasign_ultrasensitive == true, '-u')
    add(params.virasign_min_identity != null, "--min_identity ${params.virasign_min_identity}")
    add(params.virasign_min_mapped_reads != null, "--min_mapped_reads ${params.virasign_min_mapped_reads}")
    add(params.virasign_coverage_depth != null, "--coverage_depth ${params.virasign_coverage_depth}")
    add(params.virasign_coverage_breadth != null, "--coverage_breadth ${params.virasign_coverage_breadth}")
    add(params.virasign_min_nogr != null, "--min-nogr ${params.virasign_min_nogr}")
    def tail = task.ext.args?.toString()?.trim()
    def cmdOpts = (opt + (tail ? [tail] : [])).join(' ')
    def targetAccession = ''
    if (VirasignDb.isCustomAccessionDb(params)) {
        targetAccession = effectiveDbArg
    }
    def ultrasensitive = params.virasign_ultrasensitive == true
    def filteringCriteria = [:]
    if (params.virasign_min_identity != null) {
        filteringCriteria.min_identity = params.virasign_min_identity
    } else if (ultrasensitive) {
        filteringCriteria.min_identity = 70
    }
    if (params.virasign_min_mapped_reads != null) {
        filteringCriteria.min_mapped_reads = params.virasign_min_mapped_reads
    } else if (ultrasensitive) {
        filteringCriteria.min_mapped_reads = 10
    }
    if (params.virasign_coverage_depth != null) {
        filteringCriteria.coverage_depth_threshold = params.virasign_coverage_depth
    } else if (ultrasensitive) {
        filteringCriteria.coverage_depth_threshold = 0.1
    }
    if (params.virasign_coverage_breadth != null) {
        filteringCriteria.coverage_breadth_threshold = params.virasign_coverage_breadth
    } else if (ultrasensitive) {
        filteringCriteria.coverage_breadth_threshold = 0.01
    }
    if (params.virasign_min_nogr != null) {
        filteringCriteria.min_nogr = params.virasign_min_nogr
    }
    def filtering_criteria_json = groovy.json.JsonOutput.toJson(filteringCriteria)
    // No `def`: RHS references effectiveDbArg assigned without def (Nextflow 23.04).
    database_used_json = groovy.json.JsonOutput.toJson(
        VirasignDb.isCustomAccessionDb(params) ? 'Custom' : effectiveDbArg
    )

    """
    OUT='${outroot}'
    export OUT
    export TARGET_ACCESSION='${targetAccession}'
    export VIRASIGN_DB_LABEL='${virasignDbLabel}'
    export OUT_HTML='${outHtml}'
    export OUT_CSV='${outCsv}'

    # Include every sample with a per-sample final_selected JSON (empty [] when no confident hits).
    # Always run virasign --build-html: even with zero viral hits it emits the standard Metatropics
    # layout (empty reference tables / no-virus samples). Do not emit a bare placeholder page.

    if [ ! -d "\$OUT" ]; then
      echo "ERROR: Virasign results root missing: \$OUT" >&2
      exit 1
    fi

    # virasign --build-html always opens OUT/.virasign.log for writing; remove stale/root-owned log first.
    rm -f "\${OUT}/.virasign.log" || true

    virasign --build-html -o "\$OUT" ${cmdOpts}

    python3 <<'PY'
import csv
import os
from pathlib import Path

out = Path(os.environ["OUT"])
target_acc = os.environ.get("TARGET_ACCESSION", "").strip()
prefer_label = os.environ.get("VIRASIGN_DB_LABEL", "").strip()
out_html = Path(os.environ["OUT_HTML"])
out_csv = Path(os.environ["OUT_CSV"])

def accession_col(fieldnames):
    if not fieldnames:
        return None
    low = {f.lower().strip(): f for f in fieldnames}
    for key in ("accession", "virus", "reference", "reference_id", "ref"):
        if key in low:
            return low[key]
    return None

def score_csv(path: Path) -> tuple:
    # Tuple: hits, total_with_accession, label_preference, name. Zero-hit CSVs are valid.
    label_pref = 1 if (prefer_label and path.stem.endswith("_" + prefer_label)) else 0
    if not path.is_file():
        return (0, 0, label_pref, path.name)
    try:
        with path.open("r", newline="", encoding="utf-8") as handle:
            reader = csv.DictReader(handle)
            acc_col = accession_col(reader.fieldnames)
            total = 0
            matched = 0
            for row in reader:
                acc = (row.get(acc_col) or "").strip() if acc_col else ""
                if not acc:
                    continue
                total += 1
                if target_acc and acc == target_acc:
                    matched += 1
            if target_acc:
                return (matched, total, label_pref, path.name)
            return (total, total, label_pref, path.name)
    except Exception:
        return (0, 0, label_pref, path.name)

candidates = sorted(out.glob("results_summary_*.csv"))
if not candidates:
    raise SystemExit(f"ERROR: no results_summary_*.csv under {out}")

best = None
best_key = (-1, -1, -1, "")
for csv_path in candidates:
    key = score_csv(csv_path)
    if key > best_key:
        best_key = key
        best = csv_path

if best is None:
    raise SystemExit(f"ERROR: could not select a results_summary_*.csv under {out}")

html_path = best.with_suffix(".html")
if not html_path.is_file():
    raise SystemExit(f"ERROR: missing HTML for selected summary {best}")

out_html.write_bytes(html_path.read_bytes())
out_csv.write_bytes(best.read_bytes())
print(
    f"Selected summary: {html_path.name} "
    f"(hits={best_key[0]}, total_with_accession={best_key[1]})"
    + ("; no viral hits — keeping full empty layout" if best_key[0] <= 0 else "")
)
PY

# Compute consensus-derived breadth from draft consensus FASTA and merge into summary CSV.
    python3 - <<'PY'
import csv
import json
import gzip
import os
import re
from pathlib import Path

outdir = Path("${params.outdir ?: params.out_dir}")
summary_csv = Path("${outCsv}")
summary_html = Path("${outHtml}")
readcount_csv = outdir / "Summary" / "readcount" / "read_counts.csv"
cons_root = outdir / "Consensus" / "bcftools"

virasign_runtime_log = outdir / "Classification" / "virasign" / "${virasignDbLabel}" / ".virasign.log"

# Virasign background/z-score configuration (for human-readable documentation in HTML).
zscore_enabled_raw = ${zscore_json}
zscore_controls_text = ${zscore_controls_json}
virasign_blind_text = ${virasign_blind_json}
zscore_enabled = str(zscore_enabled_raw).strip().lower() in {"true","1","yes","y"}
zscore_controls_text = str(zscore_controls_text or "").strip()
virasign_blind_text = str(virasign_blind_text or "").strip()

if not zscore_enabled:
    zscore_water_msg = f"Z-score disabled (--zscore={zscore_enabled_raw})."
else:
    if zscore_controls_text:
        zscore_water_msg = f"Water controls (explicit --zscore-controls): {zscore_controls_text}"
    else:
        zscore_water_msg = "Water controls: auto-detected by Virasign (no --zscore-controls provided)."

if virasign_blind_text:
    blind_msg = f"Blind/background file (explicit --virasign_blind): {virasign_blind_text}"
else:
    blind_msg = "Blind/background file: not provided (Virasign uses defaults/auto when needed)."

# If Virasign couldn't compute Z-scores due to missing/insufficient water controls,
# the produced summary CSV will have an empty Z-score column.
# Detect that so the HTML documentation can explicitly say "none detected/used".
zscore_has_values = False
try:
    if summary_csv.exists():
        with summary_csv.open("r", newline="", encoding="utf-8") as handle:
            reader = csv.DictReader(handle)
            if reader.fieldnames:
                z_cols = [c for c in reader.fieldnames if c and c.strip().lower().startswith("z-score")]
                for row in reader:
                    for zc in z_cols:
                        raw_v = (row.get(zc) or "").strip()
                        if raw_v and raw_v not in {"—", "-"}:
                            zscore_has_values = True
                            break
                    if zscore_has_values:
                        break
except Exception:
    pass

if zscore_enabled and not zscore_has_values:
    if zscore_controls_text:
        zscore_water_msg = (
            f"Water controls provided, but none were usable/available for Z-score computation "
            f"(Virasign left Z-score empty). Provided: {zscore_controls_text}"
        )
    else:
        zscore_water_msg = (
            "Water controls: none usable/available (Virasign skipped Z-score computation; Z-score column is empty)."
        )

# Values for CSV annotation (computed here after inspecting outputs)
background_used = "yes" if (zscore_enabled and zscore_has_values) else "no"

# Determine which samples are background controls for Z-score.
# Prefer explicit `--zscore-controls` (paths or sample IDs). If not provided,
# fall back to common naming patterns (H2O/water/blank/control).
def _norm_sample_id(s: str) -> str:
    s = (s or "").strip()
    if not s:
        return ""
    for suf in (".fastq.gz", ".fq.gz", ".fastq", ".fq"):
        if s.endswith(suf):
            s = s[: -len(suf)]
            break
    # Normalise common suffixes so background sample detection is robust to
    # pipeline-added suffixes and FASTQ naming.
    # NOTE: keep \\Z escapes so Groovy/Nextflow string parsing doesn't choke.
    s = re.sub(r"\\.fastp\\Z", "", s)
    s = re.sub(r"(_T\\d+_other_T\\d+|_other_T\\d+|_T\\d+_other|_T\\d+|_other)\\Z", "", s)
    return s

def _parse_controls_list(txt: str) -> list:
    if not txt:
        return []
    out = []
    for part in str(txt).split(","):
        p = part.strip()
        if not p:
            continue
        p = os.path.basename(p)
        out.append(_norm_sample_id(p))
    return [x for x in out if x]

controls_norm = set(_parse_controls_list(zscore_controls_text))

def is_background_sample(sample: str) -> bool:
    s_norm = _norm_sample_id(sample)
    if not s_norm:
        return False
    if controls_norm:
        return s_norm in controls_norm
    s = s_norm.lower()
    # Heuristic fallback: be strict and only match typical water/blank controls.
    # Do NOT match generic substrings like "neg" because many studies encode that in sample names
    # (e.g. LASVnegRUN1_...) and it would incorrectly flag all samples as background.
    return any(k in s for k in ("h2o", "water", "blank"))

# For auto-detection mode, show exact Virasign log lines where available.
# This can include explicit control files selected or "none/insufficient controls".
zscore_runtime_lines = []
try:
    if virasign_runtime_log.exists():
        seen = set()
        with virasign_runtime_log.open("r", encoding="utf-8", errors="ignore") as handle:
            for line in handle:
                s = line.strip()
                if not s:
                    continue
                lo = s.lower()
                if ("z-score" in lo) or ("zscore" in lo) or ("water control" in lo) or ("zscore-controls" in lo):
                    if s not in seen:
                        seen.add(s)
                        zscore_runtime_lines.append(s)
except Exception:
    pass

if zscore_enabled and not zscore_controls_text and zscore_runtime_lines:
    zscore_water_msg = "Water controls: auto-detected by Virasign. " + " | ".join(zscore_runtime_lines[:3])

def safe_pct(num, den):
    if den == 0:
        return ""
    return f"{(100.0 * num / den):.2f}"

def parse_fasta_counts(path: Path):
    total = 0
    called = 0
    n_bases = 0
    gap_bases = 0
    acgt = 0
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            if not line or line.startswith(">"):
                continue
            seq = line.strip().upper()
            for ch in seq:
                if ch.isspace():
                    continue
                total += 1
                if ch == "N":
                    n_bases += 1
                else:
                    called += 1
                if ch == "-":
                    gap_bases += 1
                if ch in {"A", "C", "G", "T"}:
                    acgt += 1
    return total, called, n_bases, gap_bases, acgt

vsign_parent = outdir / "Classification" / "virasign"

def sanitize_species_slug(raw):
    if raw is None:
        return ""
    s = str(raw).strip()
    if not s:
        return ""
    s = re.sub(r"[^A-Za-z0-9._-]+", "_", s)
    s = re.sub(r"_+", "_", s).strip("_")
    return s

def virus_slug_from_hit(hit):
    acc = str(hit.get("accession") or "").strip()
    if not acc:
        return ""
    raw_sp = hit.get("organism") or hit.get("viral_species") or ""
    raw_sp = str(raw_sp).strip() if raw_sp else ""
    if not raw_sp and hit.get("description"):
        raw_sp = str(hit.get("description")).strip()[:120]
    sp = sanitize_species_slug(raw_sp)
    return f"{acc}_{sp}" if sp else acc

def load_slug_to_accession():
    m = {}
    if not vsign_parent.is_dir():
        return m
    for js in sorted(vsign_parent.rglob("*_final_selected_references.json")):
        try:
            data = json.loads(js.read_text(encoding="utf-8"))
        except Exception:
            continue
        if not isinstance(data, list):
            continue
        for hit in data:
            if not isinstance(hit, dict):
                continue
            acc = str(hit.get("accession") or "").strip()
            if not acc:
                continue
            slug = virus_slug_from_hit(hit)
            if slug:
                m[slug] = acc
    return m

slug_to_accession = load_slug_to_accession()

rows = []
by_pair = {}
if cons_root.exists():
    for fasta in sorted(cons_root.rglob("*.consensus.fasta")):
        sample = fasta.parent.name
        base = fasta.name
        suffix = ".consensus.fasta"
        virus_key = ""
        if base.endswith(suffix):
            core = base[:-len(suffix)]
            prefix = f"{sample}."
            if core.startswith(prefix):
                virus_key = core[len(prefix):]
            else:
                parts = core.split(".", 1)
                virus_key = parts[1] if len(parts) == 2 else core

        bare_acc = slug_to_accession.get(virus_key, virus_key)
        total, called, n_bases, gap_bases, acgt = parse_fasta_counts(fasta)

        # Consensus breadth (single definition):
        # fraction of unambiguous bases (A/C/G/T) in the produced consensus sequence.
        # This directly reflects all upstream filters (depth masking -> N, agreement/VAF, etc.).
        denom = total - gap_bases
        breadth = safe_pct(acgt, denom)
        strict_breadth = breadth
        rec = {
            "sample": sample,
            "accession": bare_acc,
            "consensus_breadth_pct": breadth,
            "consensus_acgt_breadth_pct": strict_breadth,
        }
        rows.append(rec)
        by_pair[(sample, bare_acc)] = rec
        if virus_key and virus_key != bare_acc:
            by_pair[(sample, virus_key)] = rec

qc_reads_by_sample = {}
readlen_med_by_sample = {}

# For the Metatropics Virasign report, "QC reads" should always mean:
# the number of reads that were actually used as INPUT for Virasign
# (post-fastplong, and post any enabled host depletion).
def strip_extensions(name: str) -> str:
    while True:
        new = re.sub(r"\\.(fastq|fq|fastp|gz|meta|csv)\\Z", "", name)
        if new == name:
            return name
        name = new

def extract_sample_name(filename: str) -> str:
    name = strip_extensions(filename)
    # Tech suffixes first so depletion tags are at the end (avoids split sample IDs).
    name = re.sub(r"_fixed\\Z", "", name)
    name = re.sub(r"\\.fastp\\Z", "", name)
    name = re.sub(r"_classification_results\\Z", "", name)
    name = re.sub(r"_viral\\Z", "", name)
    while True:
        new = re.sub(r"_(human_depleted|host_depleted)\\Z", "", name)
        new = re.sub(r"_(human|host)\\Z", "", new)
        new = re.sub(r"(?i)_other\\Z", "", new)
        if new == name:
            break
        name = new
    return name

def count_fastq_gz_reads(path: Path) -> int:
    n = 0
    with gzip.open(path, "rt", errors="replace") as fh:
        while True:
            l1 = fh.readline()
            if not l1:
                break
            fh.readline()
            fh.readline()
            fh.readline()
            n += 1
    return n

def median_from_counts(counts: dict) -> str:
    # Exact median from a {length: count} histogram.
    if not counts:
        return ""
    total = sum(int(v) for v in counts.values() if v)
    if total <= 0:
        return ""
    # 0-based median indices in the sorted multiset
    lo = (total - 1) // 2
    hi = total // 2
    seen = 0
    lo_val = None
    hi_val = None
    for length in sorted(counts.keys()):
        c = int(counts.get(length) or 0)
        if c <= 0:
            continue
        nxt = seen + c
        if lo_val is None and lo < nxt:
            lo_val = length
        if hi_val is None and hi < nxt:
            hi_val = length
        if lo_val is not None and hi_val is not None:
            break
        seen = nxt
    if lo_val is None or hi_val is None:
        return ""
    return str(int(round((lo_val + hi_val) / 2.0)))

def fastq_gz_length_counts(path: Path) -> dict:
    # Exact scan over all reads; store only a histogram (length -> count).
    counts = {}
    with gzip.open(path, "rt", errors="replace") as fh:
        while True:
            h = fh.readline()
            if not h:
                break
            seq = fh.readline()
            if not seq:
                break
            fh.readline()
            fh.readline()
            L = len(seq.strip())
            counts[L] = counts.get(L, 0) + 1
    return counts

def count_dir(directory: Path, pattern: re.Pattern) -> dict:
    out = {}
    length_counts = {}
    if not directory.exists():
        return out
    # rglob: support nested layouts (e.g. Reads/fastplong/<sample>/*.fastq.gz).
    for p in directory.rglob("*"):
        if not p.is_file():
            continue
        if not pattern.search(p.name):
            continue
        sample = extract_sample_name(p.name)
        out[sample] = out.get(sample, 0) + count_fastq_gz_reads(p)
        try:
            c = fastq_gz_length_counts(p)
            if c:
                agg = length_counts.setdefault(sample, {})
                for k, v in c.items():
                    agg[k] = agg.get(k, 0) + int(v)
        except Exception:
            pass
    # Store per-sample median read length.
    for s, counts in length_counts.items():
        readlen_med_by_sample[s] = median_from_counts(counts)
    return out

reads_root = outdir / "Reads"
# Prefer the most-depleted stage if present (this matches readsForViralClassification).
qc_reads_by_sample = count_dir(reads_root / "nohost", re.compile(r"_(host_depleted|other)\\.(fastq|fq)\\.gz\\Z"))
if not qc_reads_by_sample:
    qc_reads_by_sample = count_dir(reads_root / "nohuman", re.compile(r"_(human_depleted|other)\\.(fastq|fq)\\.gz\\Z"))
if not qc_reads_by_sample:
    qc_reads_by_sample = count_dir(reads_root / "fastplong", re.compile(r"\\.fastp\\.(fastq|fq)\\.gz\\Z"))

# As a last resort, fall back to whatever readcount produced (if available).
if not qc_reads_by_sample and readcount_csv.exists():
    try:
        with readcount_csv.open("r", newline="", encoding="utf-8") as handle:
            reader = csv.DictReader(handle)
            for row in reader:
                sample = (row.get("sample") or "").strip()
                v = (row.get("trimmed_reads") or "").strip()
                if sample:
                    qc_reads_by_sample[sample] = v
    except Exception:
        qc_reads_by_sample = {}

qc_map_json = json.dumps(qc_reads_by_sample, separators=(",", ":"))
readlen_map_json = json.dumps(readlen_med_by_sample, separators=(",", ":"))

def mean_read_length_fastq_gz(path: Path):
    # Mean sequence length across all reads in a gzipped FASTQ.
    n = 0
    total = 0
    with gzip.open(path, "rt", errors="replace") as fh:
        while True:
            h = fh.readline()
            if not h:
                break
            seq = fh.readline()
            if not seq:
                break
            fh.readline()
            fh.readline()
            total += len(seq.strip())
            n += 1
    if n <= 0:
        return None
    return float(total) / float(n)

def estimate_avg_len_from_hit_json(path: Path):
    # Fallback: depth * ref_len / mapped_reads from per-hit Virasign JSON.
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None
    hit = payload.get("hit") if isinstance(payload, dict) else None
    if not isinstance(hit, dict):
        hit = payload if isinstance(payload, dict) else None
    if not isinstance(hit, dict):
        return None
    try:
        mapped = float(hit.get("mapped_reads") or 0)
        depth = float(hit.get("coverage_depth") or 0)
        ref_len = None
        cov = hit.get("coverage_profile") or {}
        if isinstance(cov, dict) and cov.get("ref_len"):
            ref_len = float(cov.get("ref_len"))
        if mapped <= 0 or depth <= 0 or not ref_len:
            return None
        return (depth * ref_len) / mapped
    except Exception:
        return None

# Per viral hit: average length of reads mapped to that reference (mread.fastq.gz).
# Layout: Classification/virasign/<DB>/<sample>/<accession>/mread.fastq.gz
avg_readlen_by_pair = {}
if vsign_parent.is_dir():
    for fq in sorted(vsign_parent.rglob("mread.fastq.gz")):
        try:
            acc = fq.parent.name
            sample = fq.parent.parent.name
        except Exception:
            continue
        try:
            mean_len = mean_read_length_fastq_gz(fq)
        except Exception:
            mean_len = None
        if mean_len is None:
            jp = fq.parent / f"{acc}.json"
            if jp.is_file():
                mean_len = estimate_avg_len_from_hit_json(jp)
        if mean_len is None:
            continue
        avg_readlen_by_pair[(sample, acc)] = round(mean_len, 1)
    # Also accept alternate mapped-reads FASTQ names when mread is absent.
    for fq in sorted(vsign_parent.rglob("*_mapped_reads.fastq.gz")):
        try:
            acc = fq.parent.name
            sample = fq.parent.parent.name
        except Exception:
            continue
        if (sample, acc) in avg_readlen_by_pair:
            continue
        try:
            mean_len = mean_read_length_fastq_gz(fq)
        except Exception:
            mean_len = None
        if mean_len is None:
            continue
        avg_readlen_by_pair[(sample, acc)] = round(mean_len, 1)
    # Fallback estimate from per-hit JSON when no mapped FASTQ is present.
    # Per-accession files live at <DB>/<sample>/<accession>/<accession>.json
    for jp in sorted(vsign_parent.rglob("*.json")):
        if jp.stem != jp.parent.name:
            continue
        acc = jp.stem
        sample = jp.parent.parent.name
        if (sample, acc) in avg_readlen_by_pair:
            continue
        mean_len = estimate_avg_len_from_hit_json(jp)
        if mean_len is None:
            continue
        avg_readlen_by_pair[(sample, acc)] = round(mean_len, 1)

avg_readlen_map = {}
for (sample, acc), v in avg_readlen_by_pair.items():
    avg_readlen_map.setdefault(sample, {})[acc] = v
avg_readlen_map_json = json.dumps(avg_readlen_map, separators=(",", ":"))

if summary_csv.exists():
    with summary_csv.open("r", newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        in_fields = list(reader.fieldnames or [])
        data = list(reader)

    low = {f.lower().strip(): f for f in in_fields}
    sample_col = None
    for key in ("sample", "sample_id", "sampleid"):
        if key in low:
            sample_col = low[key]
            break
    accession_col = None
    for key in ("accession", "virus", "reference", "reference_id", "ref"):
        if key in low:
            accession_col = low[key]
            break
    zscore_cols = []
    for f in in_fields:
        fl = (f or "").lower().strip()
        if fl.startswith("z-score") or fl in ("zscore", "z_score"):
            zscore_cols.append(f)
    zscore_col = zscore_cols[0] if zscore_cols else None
    qc_header = "QC reads"
    # Per-hit average mapped-read length (replaces older sample-level median column name).
    readlen_header = "Avg Read Length"
    old_readlen_headers = {"Read Length (Med)", "Avg Read Length", "Read Length (Avg)"}
    consensus_header = "Consensus Breadth (%)"
    bg_used_header = "Background"

    out_fields = list(in_fields)

    # Remove any old technical consensus header so we can re-add consistently.
    out_fields = [f for f in out_fields if f != "consensus_breadth_pct"]
    out_fields = [f for f in out_fields if f != bg_used_header]
    out_fields = [f for f in out_fields if f not in old_readlen_headers]

    # Place Background after Sample when Sample column exists, otherwise keep first.
    if sample_col and sample_col in out_fields:
        sample_idx = out_fields.index(sample_col)
        out_fields.insert(sample_idx + 1, bg_used_header)
    else:
        out_fields = [bg_used_header] + out_fields

    # Enforce QC column before mapped reads.
    if qc_header in out_fields:
        out_fields.remove(qc_header)
    if "Mapped Reads (#)" in out_fields:
        mapped_idx = out_fields.index("Mapped Reads (#)")
        out_fields.insert(mapped_idx, qc_header)
    else:
        out_fields.append(qc_header)

    # Insert per-hit average read length after Mapped Reads (#) when present.
    if "Mapped Reads (#)" in out_fields:
        idx = out_fields.index("Mapped Reads (#)")
        out_fields.insert(idx + 1, readlen_header)
    else:
        out_fields.append(readlen_header)

    # Add consensus column as the last column.
    if consensus_header in out_fields:
        out_fields.remove(consensus_header)
    out_fields.append(consensus_header)

    if sample_col:
        # Optional sample-level fallback when each sample has a single consensus.
        by_sample = {}
        for rec in rows:
            by_sample.setdefault(rec["sample"], []).append(rec)
        def _to_float(v):
            if v is None:
                return None
            s = str(v).replace("📊", "").replace("%", "").strip()
            if not s:
                return None
            try:
                return float(s)
            except Exception:
                return None
        for row in data:
            sample = (row.get(sample_col) or "").strip()
            acc = (row.get(accession_col) or "").strip() if accession_col else ""
            hit = by_pair.get((sample, acc))
            if hit is None and not acc:
                sample_hits = by_sample.get(sample, [])
                if len(sample_hits) == 1:
                    hit = sample_hits[0]
            if zscore_enabled and zscore_has_values:
                row[bg_used_header] = "yes" if is_background_sample(sample) else "no"
                # Controls are background only — never report a numeric Z-score on them.
                if is_background_sample(sample) and zscore_cols:
                    for zc in zscore_cols:
                        row[zc] = "-"
            else:
                # If Z-score is not used (disabled or unusable), make this explicit instead of leaving blank.
                row[bg_used_header] = "no"
            row[qc_header] = qc_reads_by_sample.get(sample, "")
            avg_rl = avg_readlen_by_pair.get((sample, acc))
            row[readlen_header] = "" if avg_rl is None else f"{avg_rl:.1f}"
            cons = None if hit is None else _to_float(hit.get("consensus_breadth_pct"))
            if cons is None:
                row[consensus_header] = ""
            else:
                # Guardrail only: consensus breadth is a percentage and must not exceed 100.
                if cons > 100.0:
                    cons = 100.0
                row[consensus_header] = f"{cons:.2f}"
    else:
        for row in data:
            row[qc_header] = ""
            row[bg_used_header] = "no"
            row[readlen_header] = ""
            row[consensus_header] = ""

    with summary_csv.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=out_fields)
        writer.writeheader()
        writer.writerows(data)

if summary_html.exists():
    import json
    import sys

    text = summary_html.read_text(encoding="utf-8")

    # Branding: Metatropics report header (keep database suffix, e.g. " - RVDB").
    text = text.replace("Virasign Results Summary", "Metatropics Results Summary")
    text = text.replace(
        "Viral Read ASSIGNment from nanopore sequencing",
        "Human viral pathogen identification from nanopore metagenomic sequencing",
    )

    # Virasign --build-html often leaves metadata.filtering_criteria / database_used empty
    # (especially with zero hits). Patch from pipeline params so the config panel matches the
    # header Database label. Empty database_used makes Virasign JS fall through to "Custom".
    filtering_criteria = ${filtering_criteria_json}
    database_used = ${database_used_json}
    database_source = ${virasign_db_label_json}
    marker = "const samplesData = "
    idx = text.find(marker)
    if idx != -1:
        start = idx + len(marker)
        heat_idx = text.find("const heatmapData", start)
        end = text.rfind(";", start, heat_idx) if heat_idx != -1 else -1
        if end != -1:
            try:
                data = json.loads(text[start:end])
                for sample_data in data.values():
                    if not isinstance(sample_data, dict):
                        continue
                    for db_block in sample_data.values():
                        if not isinstance(db_block, dict):
                            continue
                        meta = db_block.setdefault("metadata", {})
                        if filtering_criteria:
                            meta["filtering_criteria"] = dict(filtering_criteria)
                        if database_used:
                            meta["database_used"] = database_used
                        if database_source:
                            meta["database_source"] = database_source
                text = text[:start] + json.dumps(data, separators=(",", ":")) + text[end:]
            except Exception as exc:
                print(f"WARNING: could not patch database/filtering metadata in summary HTML: {exc}", file=sys.stderr)


    # If the pipeline is re-run, remove any previously injected consensus panel.
    # Use plain string operations (avoid regex backslash parsing issues).
    section_start = text.find('<section id="consensus-breadth"')
    if section_start != -1:
        section_end = text.find('</section>', section_start)
        if section_end != -1:
            section_end = section_end + len('</section>')
            # Often the section is immediately followed by a <script>...</script>.
            script_start = text.find('<script', section_end)
            if script_start != -1:
                script_end = text.find('</script>', script_start)
                if script_end != -1:
                    script_end = script_end + len('</script>')
                    text = text[:section_start] + text[script_end:]
                else:
                    text = text[:section_start] + text[section_end:]
            else:
                text = text[:section_start] + text[section_end:]

    # Ensure the per-sample "Download Table (CSV)" header matches the appended column.
    text = text.replace(
        "let csv = 'Accession,Organism,Viral Species,Nextclade Clade,Segment,Mapped Reads (#),Identity (%),Coverage Depth (x),Coverage Breadth (%),NOGR (#/%),Z-score\\n';",
        "let csv = 'Accession,Organism,Viral Species,Nextclade Clade,Segment,Mapped Reads (#),Identity (%),Coverage Depth (x),Coverage Breadth (%),NOGR (#/%),Z-score (species),Z-score (genus),Consensus Breadth (%)\\n';",
        1
    )
    # Backward-compatible replace if HTML was built with an older Virasign header.
    text = text.replace(
        "let csv = 'Accession,Organism,Viral Species,Nextclade Clade,Segment,Mapped Reads (#),Identity (%),Coverage Depth (x),Coverage Breadth (%),NOGR (#/kb/%),Z-score\\n';",
        "let csv = 'Accession,Organism,Viral Species,Nextclade Clade,Segment,Mapped Reads (#),Identity (%),Coverage Depth (x),Coverage Breadth (%),NOGR (#/%),Z-score (species),Z-score (genus),Consensus Breadth (%)\\n';",
        1
    )
    text = text.replace(
        "let csv = 'Accession,Organism,Viral Species,Nextclade Clade,Segment,Mapped Reads (#),Identity (%),Coverage Depth (x),Coverage Breadth (%),NOGR (#/bases),Z-score\\n';",
        "let csv = 'Accession,Organism,Viral Species,Nextclade Clade,Segment,Mapped Reads (#),Identity (%),Coverage Depth (x),Coverage Breadth (%),NOGR (#/%),Z-score (species),Z-score (genus),Consensus Breadth (%)\\n';",
        1
    )
    if "Consensus Breadth (%)" not in text:
        text = text.replace("Z-score\\n';", "Z-score,Consensus Breadth (%)\\n';", 1)

    # Compact map used by client-side JS to populate the new table column.
    # Structure: { "<sample>": { "<accession>": <float breadth_pct> } }
    cons_map = {}
    for rec in rows:
        s = (rec.get("sample") or "").strip()
        a = (rec.get("accession") or "").strip()
        v = rec.get("consensus_breadth_pct")
        if not s or not a or v in (None, ""):
            continue
        try:
            cons_map.setdefault(s, {})[a] = float(v)
        except Exception:
            pass
    cons_map_json = json.dumps(cons_map, separators=(",", ":"))

    # Sample -> Background (yes/no) map for CSV downloads triggered from HTML.
    bg_map = {}
    try:
        if sample_col:
            for row in data:
                s = (row.get(sample_col) or "").strip()
                if not s:
                    continue
                bg_map[s] = (row.get(bg_used_header) or "").strip()
    except Exception:
        bg_map = {}
    bg_map_json = json.dumps(bg_map, separators=(",", ":"))

    # Resolve which water/background samples were actually used for Z-score.
    # Prefer names embedded by Virasign in samplesData.zscore_controls (truth of the run).
    zscore_controls_used = []
    try:
        m_sd = re.search(r"const samplesData\\s*=\\s*", text)
        if m_sd:
            samples_obj, _ = json.JSONDecoder().raw_decode(text, m_sd.end())
            seen = []
            for _sname, dbs in (samples_obj or {}).items():
                for _db, payload in (dbs or {}).items():
                    for ref in (payload or {}).get("references") or []:
                        for c in ref.get("zscore_controls") or []:
                            c = str(c).strip()
                            if c and c not in seen:
                                seen.append(c)
            zscore_controls_used = seen
    except Exception:
        zscore_controls_used = []

    if not zscore_controls_used and controls_norm:
        zscore_controls_used = sorted(controls_norm)
    if not zscore_controls_used:
        zscore_controls_used = sorted(s for s, v in bg_map.items() if str(v).strip().lower() == "yes")

    if not zscore_enabled:
        zscore_mode = "disabled"
        zscore_mode_label = "disabled"
        zscore_water_msg = f"Z-score disabled (--zscore={zscore_enabled_raw})."
    elif zscore_controls_text:
        zscore_mode = "manual"
        zscore_mode_label = "manually selected"
        names = ", ".join(zscore_controls_used) if zscore_controls_used else zscore_controls_text
        if zscore_has_values:
            zscore_water_msg = f"Water controls (manually selected): {names}"
        else:
            zscore_water_msg = (
                f"Water controls provided, but none were usable/available for Z-score computation. "
                f"Provided: {names}"
            )
    elif zscore_controls_used and zscore_has_values:
        zscore_mode = "auto"
        zscore_mode_label = "auto-detected"
        zscore_water_msg = f"Water controls (auto-detected): {', '.join(zscore_controls_used)}"
    else:
        zscore_mode = "none"
        zscore_mode_label = "none available"
        zscore_water_msg = (
            "Water controls: none usable/available (Z-score not computed)."
        )

    zscore_controls_json = json.dumps(zscore_controls_used, separators=(",", ":"))
    zscore_mode_json = json.dumps(zscore_mode, separators=(",", ":"))
    zscore_mode_label_json = json.dumps(zscore_mode_label, separators=(",", ":"))
    zscore_water_msg_json = json.dumps(zscore_water_msg, separators=(",", ":"))

    # The summary script lives in bin/ so this process stays under Groovy's 65535-character string limit (Nextflow 23.04).
    _inject_js_name = "metatropics_summary_inject.js"
    _inject_js_path = next(
        (
            Path(entry) / _inject_js_name
            for entry in os.environ.get("PATH", "").split(os.pathsep)
            if entry and (Path(entry) / _inject_js_name).is_file()
        ),
        None,
    )
    if _inject_js_path is None:
        raise SystemExit(
            "ERROR: metatropics_summary_inject.js not found on PATH "
            "(expected in the pipeline bin directory)"
        )
    inj_script = _inject_js_path.read_text(encoding="utf-8")

    inj_script = inj_script.replace("__CONS_MAP_JSON__", cons_map_json)
    inj_script = inj_script.replace("__QC_READS_MAP_JSON__", qc_map_json)
    inj_script = inj_script.replace("__READLEN_MAP_JSON__", readlen_map_json)
    inj_script = inj_script.replace("__AVG_READLEN_MAP_JSON__", avg_readlen_map_json)
    inj_script = inj_script.replace("__BG_MAP_JSON__", bg_map_json)
    inj_script = inj_script.replace("__ZSCORE_CONTROLS_JSON__", zscore_controls_json)
    inj_script = inj_script.replace("__ZSCORE_MODE_JSON__", zscore_mode_json)
    inj_script = inj_script.replace("__ZSCORE_MODE_LABEL_JSON__", zscore_mode_label_json)
    inj_script = inj_script.replace("__ZSCORE_WATER_MSG_JSON__", zscore_water_msg_json)

    if 'data-col="consensus_breadth_pct"' not in text:
        if "</body>" in text:
            text = text.replace("</body>", inj_script + "\\n</body>", 1)
        else:
            text = text + "\\n" + inj_script

    summary_html.write_text(text, encoding="utf-8")
PY

    # Samples that never reached Virasign: still list them as empty no-hit in CSV/HTML.
    metatropics_inject_missing_samples.py \
        --outdir '${params.outdir ?: params.out_dir}' \
        --csv '${outCsv}' \
        --html '${outHtml}' \
        --samplesheet ${samplesheet_json} \
        --db-label ${virasign_db_label_json}

    # Keep the shared Classification/virasign tree focused on per-sample outputs only.
    rm -f "${outroot}"/results_summary_*.html "${outroot}"/results_summary_*.csv "${outroot}"/.virasign.log || true

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        virasign: \$(virasign --version 2>&1 | head -n1 || echo 'unknown')
    END_VERSIONS
    """
}

