
<script>
(function(){
  const consensusMap = __CONS_MAP_JSON__;
  const qcReadsMap = __QC_READS_MAP_JSON__;
  const readLenMap = __READLEN_MAP_JSON__;
  const avgReadLenMap = __AVG_READLEN_MAP_JSON__;
  const bgMap = __BG_MAP_JSON__;
  const zscoreControls = __ZSCORE_CONTROLS_JSON__;
  const zscoreMode = __ZSCORE_MODE_JSON__;
  const zscoreModeLabel = __ZSCORE_MODE_LABEL_JSON__;
  const zscoreWaterMsg = __ZSCORE_WATER_MSG_JSON__;

  function getVal(sampleName, accession){
    if (!consensusMap || !consensusMap[sampleName]) return null;
    const v = consensusMap[sampleName][accession];
    if (v === undefined || v === null || v === '') return null;
    return Number(v);
  }
  

  function getQcReads(sampleName){
    if (!qcReadsMap) return '';
    const v = qcReadsMap[sampleName];
    return (v === undefined || v === null) ? '' : String(v);
  }

  function getReadLenMed(sampleName){
    if (!readLenMap) return '';
    const v = readLenMap[sampleName];
    return (v === undefined || v === null) ? '' : String(v);
  }

  function getAvgReadLen(sampleName, accession){
    if (!avgReadLenMap || !avgReadLenMap[sampleName]) return '';
    const v = avgReadLenMap[sampleName][accession];
    return (v === undefined || v === null || v === '') ? '' : String(v);
  }

  function getBackground(sampleName){
    if (!bgMap) return '';
    const v = bgMap[sampleName];
    return (v === undefined || v === null) ? '' : String(v);
  }

  function ensureHeader(table, sampleName){
    if (!table) return;
    const headerRows = table.querySelectorAll('thead tr');
    if (headerRows.length < 2) return;
    const filterRow = headerRows[0];
    const mainRow = headerRows[1];
    const colgroup = table.querySelector('colgroup');

    // Avg mapped read length (visible) — place after Mapped Reads (#).
    function insertAfterMappedReads(parent, el, findMapped) {
      const mapped = findMapped(parent);
      if (mapped) {
        mapped.after(el);
      } else {
        parent.appendChild(el);
      }
    }

    if (colgroup && !colgroup.querySelector('col[data-col="avg_read_length"]')) {
      const col = document.createElement('col');
      col.setAttribute('data-col', 'avg_read_length');
      col.style.width = '110px';
      const cols = Array.from(colgroup.querySelectorAll('col'));
      // Base colgroup has 11 cols; Mapped Reads is index 5.
      if (cols.length > 5) {
        cols[5].after(col);
      } else {
        colgroup.appendChild(col);
      }
    }
    if (filterRow && !filterRow.querySelector('th[data-col="avg_read_length"]')) {
      const filterTh = document.createElement('th');
      filterTh.setAttribute('data-col', 'avg_read_length');
      const inp = document.createElement('input');
      inp.type = 'text';
      inp.placeholder = 'Min Len';
      inp.addEventListener('keyup', function () {
        if (typeof window.applyAllFilters === 'function') window.applyAllFilters(sampleName);
      });
      inp.style.width = '100%';
      inp.style.padding = '5px 6px';
      inp.style.border = '1px solid #ddd';
      inp.style.borderRadius = '4px';
      inp.style.fontSize = '0.9em';
      inp.style.boxSizing = 'border-box';
      filterTh.appendChild(inp);
      insertAfterMappedReads(filterRow, filterTh, function(row){
        const inputs = row.querySelectorAll('input[type="text"]');
        for (let i = 0; i < inputs.length; i++) {
          if ((inputs[i].getAttribute('placeholder') || '') === 'Min Reads') {
            return inputs[i].closest('th');
          }
        }
        return null;
      });
    }
    if (mainRow && !mainRow.querySelector('th[data-col="avg_read_length"]')) {
      const th = document.createElement('th');
      th.textContent = 'Avg Read Length';
      th.setAttribute('data-col', 'avg_read_length');
      th.className = 'stats sortable';
      th.setAttribute('data-sort', 'avg_read_length');
      th.title = 'Average length of reads mapped to this viral reference';
      insertAfterMappedReads(mainRow, th, function(row){
        return row.querySelector('th[data-sort="mapped_reads"]');
      });
    }

    if (colgroup && !colgroup.querySelector('col[data-col="consensus_breadth_pct"]')) {
      const col = document.createElement('col');
      col.setAttribute('data-col', 'consensus_breadth_pct');
      col.style.width = '140px';
      col.style.display = 'none';
      colgroup.appendChild(col);
    }

    if (filterRow && !filterRow.querySelector('th[data-col="consensus_breadth_pct"]')) {
      const filterTh = document.createElement('th');
      filterTh.setAttribute('data-col', 'consensus_breadth_pct');
      filterTh.style.display = 'none';

      // Add a numeric filter for consensus breadth when the column is toggled on.
      const inp = document.createElement('input');
      inp.type = 'text';
      inp.placeholder = 'Min Breadth';
      inp.addEventListener('keyup', function () {
        // applyAllFilters is defined in the base HTML (already on window)
        if (typeof window.applyAllFilters === 'function') window.applyAllFilters(sampleName);
      });
      inp.style.width = '100%';
      inp.style.padding = '5px 6px';
      inp.style.border = '1px solid #ddd';
      inp.style.borderRadius = '4px';
      inp.style.fontSize = '0.9em';
      inp.style.boxSizing = 'border-box';
      filterTh.appendChild(inp);

      filterRow.appendChild(filterTh);
    }

    if (!mainRow.querySelector('th[data-col="consensus_breadth_pct"]')) {
      const th = document.createElement('th');
      th.textContent = 'Consensus Breadth (%)';
      th.setAttribute('data-col', 'consensus_breadth_pct');
      th.className = 'stats sortable';
      th.setAttribute('data-sort', 'consensus_breadth_pct');
      th.style.display = 'none';
      mainRow.appendChild(th);
    }
  }

  function ensureToggleButton(sampleName){
    const sampleSection = document.getElementById('sample-' + sampleName);
    if (!sampleSection) return;
    const header = sampleSection.querySelector('.table-header');
    if (!header) return;
    if (header.querySelector('button[data-role="consensus-metrics-toggle"]')) return;

    const button = document.createElement('button');
    button.type = 'button';
    button.setAttribute('data-role', 'consensus-metrics-toggle');
    button.textContent = 'Consensus Metrics';
    button.addEventListener('click', function(){
      toggleConsensusColumn(sampleName);
    });

    // Keep download button + consensus toggle grouped on the right.
    let rightActions = header.querySelector('div[data-role="consensus-right-actions"]');
    const downloadBtn = header.querySelector('button[onclick^="downloadTableAsCSV"]');
    if (!rightActions) {
      rightActions = document.createElement('div');
      rightActions.setAttribute('data-role', 'consensus-right-actions');
      rightActions.style.display = 'flex';
      rightActions.style.gap = '0.6rem';
      rightActions.style.alignItems = 'center';

      if (downloadBtn) {
        header.insertBefore(rightActions, downloadBtn);
        rightActions.appendChild(downloadBtn);
      } else {
        header.appendChild(rightActions);
      }
    }

    rightActions.appendChild(button);
  }

  function setConsensusColumnVisibility(sampleName, visible){
    const table = document.getElementById('table-' + sampleName);
    const tbody = document.getElementById('tbody-' + sampleName);
    if (!table) return;

    const headerRows = table.querySelectorAll('thead tr');
    if (headerRows.length < 2) return;
    const filterRow = headerRows[0];
    const mainRow = headerRows[1];

    // 1) Consensus column itself
    table.querySelectorAll('th[data-col="consensus_breadth_pct"], td[data-col="consensus_breadth_pct"]').forEach(el => {
      el.style.display = visible ? '' : 'none';
    });

    // 1b) Spacing fix: when table-layout is fixed, hiding only th/td can leave
    // whitespace reserved for hidden columns. Hide the <col> elements too.
    const colgroup = table.querySelector('colgroup');
    if (colgroup) {
      const cols = Array.from(colgroup.querySelectorAll('col'));
      if (!visible) {
        // Default view: keep original layout, but do NOT reserve width for the
        // consensus column (we already hide the corresponding th/td above).
        table.style.tableLayout = 'fixed';
        cols.forEach(c => {
          if (c.getAttribute('data-col') === 'consensus_breadth_pct') {
            c.style.display = 'none';
          } else {
            c.style.display = '';
          }
        });
      } else {
        table.style.tableLayout = 'auto';

        const ths = Array.from(mainRow.querySelectorAll('th'));
        const n = Math.min(cols.length, ths.length);
        for (let i = 0; i < n; i++) {
          const th = ths[i];
          if (!th) {
            cols[i].style.display = 'none';
            continue;
          }
          const dataCol = th.getAttribute('data-col');
          const dataSort = th.getAttribute('data-sort');
          const show =
            (dataCol === 'consensus_breadth_pct') ||
            (dataCol === 'avg_read_length') ||
            (dataSort === 'breadth') ||
            (dataSort === 'nogr_regions') ||
            (dataSort === 'zscore') ||
            (dataSort === 'zscore_species') ||
            (dataSort === 'zscore_genus') ||
            (dataSort === 'avg_read_length') ||
            (!dataSort); // base columns have no data-sort
          cols[i].style.display = show ? '' : 'none';
        }
        // If the colgroup has extra columns, hide them.
        for (let i = n; i < cols.length; i++) {
          cols[i].style.display = 'none';
        }
      }
    }

    // 2) Hide/show the other columns when consensus view is enabled
    //    Compact view (keep these):
    //      Accession | Organism | Viral species | Clade | Segment | Breadth | Consensus Breadth | NOGR | Z-score
    //    Hide only: Mapped reads (#), Identity, Depth.
    const hideMainSorts = ['mapped_reads','identity','depth'];
    hideMainSorts.forEach(s => {
      const th = mainRow.querySelector('th[data-sort="' + s + '"]');
      if (th) th.style.display = visible ? 'none' : '';
    });

    const hidePlaceholders = new Set(['Min Reads','Min ID','Min Depth']);
    if (filterRow) {
      filterRow.querySelectorAll('input[type="text"]').forEach(inp => {
        const ph = inp.getAttribute('placeholder') || '';
        const th = inp.closest('th');
        if (!th) return;
        if (hidePlaceholders.has(ph)) th.style.display = visible ? 'none' : '';
      });
    }

    if (tbody) {
      tbody.querySelectorAll('tr').forEach(row => {
        const tds = Array.from(row.querySelectorAll('td')).filter(td => {
          const col = td.getAttribute('data-col') || '';
          return col !== 'avg_read_length' && col !== 'consensus_breadth_pct';
        });
        // Expected base columns (0-based), excluding injected cols:
        // 0 Accession, 1 Organism, 2 Viral Species, 3 Clade, 4 Segment,
        // 5 Mapped Reads, 6 Identity, 7 Depth, 8 Breadth, 9 NOGR, 10 Z-score
        // Hide for compact view: Mapped Reads, Identity, Depth.
        // Avg Read Length stays visible (injected after Mapped Reads).
        if (tds.length > 7) {
          tds[5].style.display = visible ? 'none' : '';
          tds[6].style.display = visible ? 'none' : '';
          tds[7].style.display = visible ? 'none' : '';
        }
        const tdLen = row.querySelector('td[data-col="avg_read_length"]');
        if (tdLen) tdLen.style.display = '';
        if (tds[8]) tds[8].style.display = '';
        if (tds[9]) tds[9].style.display = '';
        if (tds[10]) tds[10].style.display = '';
      });
    }

    const sampleSection = document.getElementById('sample-' + sampleName);
    if (sampleSection) {
      const button = sampleSection.querySelector('button[data-role="consensus-metrics-toggle"]');
      if (button) {
        button.textContent = visible ? 'Hide Consensus Metrics' : 'Consensus Metrics';
      }
    }
  }

  function toggleConsensusColumn(sampleName){
    const table = document.getElementById('table-' + sampleName);
    if (!table) return;
    const header = table.querySelector('th[data-col="consensus_breadth_pct"]');
    const visible = !!(header && header.style.display !== 'none');
    setConsensusColumnVisibility(sampleName, !visible);
  }

  function injectForSample(sampleName){
    const table = document.getElementById('table-' + sampleName);
    const tbody = document.getElementById('tbody-' + sampleName);
    if (!table || !tbody) return;

    ensureHeader(table, sampleName);
    ensureToggleButton(sampleName);

    tbody.querySelectorAll('tr').forEach(row => {
      const accession = row.getAttribute('data-accession') || '';
      let v = getVal(sampleName, accession);
      if (v !== null && v > 100) v = 100;
      const txt = (v === null) ? '-' : (v.toFixed(2) + '%');

      // Per-hit average mapped read length — insert after Mapped Reads (#).
      const avgRlRaw = getAvgReadLen(sampleName, accession);
      const avgRlNum = avgRlRaw === '' ? null : Number(avgRlRaw);
      let tdLen = row.querySelector('td[data-col="avg_read_length"]');
      if (!tdLen){
        tdLen = document.createElement('td');
        tdLen.setAttribute('data-col','avg_read_length');
        tdLen.className = 'stats';
      }
      row.setAttribute('data-avg-read-length', avgRlNum === null || isNaN(avgRlNum) ? '' : String(avgRlNum));
      tdLen.textContent = (avgRlNum === null || isNaN(avgRlNum)) ? '-' : avgRlNum.toFixed(1);
      const baseTds = Array.from(row.querySelectorAll('td')).filter(td => {
        const col = td.getAttribute('data-col') || '';
        return col !== 'avg_read_length' && col !== 'consensus_breadth_pct';
      });
      if (baseTds.length > 5) {
        baseTds[5].after(tdLen);
      } else if (!tdLen.parentNode) {
        row.appendChild(tdLen);
      }

      let td = row.querySelector('td[data-col="consensus_breadth_pct"]');
      if (!td){
        td = document.createElement('td');
        td.setAttribute('data-col','consensus_breadth_pct');
        td.className = 'stats';
        td.style.display = 'none';
        row.appendChild(td);
      }
      row.setAttribute('data-consensus-breadth', v === null ? '' : String(v));
      td.textContent = txt;
    });

    setConsensusColumnVisibility(sampleName, false);
  }

  // Inject Z-score water-control info into the Summary banner and Pipeline Configuration.
  function zscoreControlsDisplay(){
    if (Array.isArray(zscoreControls) && zscoreControls.length) {
      return zscoreControls.join(', ');
    }
    return zscoreWaterMsg || 'none';
  }

  function injectZscoreControlsBanner(){
    const summary = document.querySelector('.summary');
    if (!summary || document.getElementById('zscore-controls-banner')) return;
    const div = document.createElement('div');
    div.id = 'zscore-controls-banner';
    div.style.margin = '1rem 0 0';
    div.style.padding = '0.85rem 1rem';
    div.style.background = '#f0f7ff';
    div.style.border = '1px solid #c5daf5';
    div.style.borderRadius = '8px';
    div.style.color = '#1a365d';
    div.style.fontSize = '0.95em';
    const modeTxt = zscoreModeLabel ? (' (' + zscoreModeLabel + ')') : '';
    div.innerHTML =
      '<strong>Z-score water controls</strong>' +
      '<span style="opacity:0.75">' + modeTxt + '</span>: ' +
      '<span>' + zscoreControlsDisplay() + '</span>';
    summary.appendChild(div);
  }

  injectZscoreControlsBanner();

  const origPopulateTable = window.populateTable;
  if (typeof origPopulateTable === 'function'){
    window.populateTable = function(sampleName){
      origPopulateTable(sampleName);
      injectForSample(sampleName);
    };
  }

  // Override downloadTableAsCSV so the downloaded CSV includes QC reads + per-hit avg read length + consensus breadth.
  const origDownloadTableAsCSV = window.downloadTableAsCSV;
  window.downloadTableAsCSV = function(sampleName) {
    const tbody = document.getElementById('tbody-' + sampleName);
    if (!tbody) return;

    const NL = String.fromCharCode(10);
    let csv = 'Sample,Background,Accession,Organism,Viral Species,Nextclade Clade,Segment,QC reads,Mapped Reads (#),Avg Read Length,Identity (%),Coverage Depth (x),Coverage Breadth (%),NOGR (#/%),Z-score (species),Z-score (genus),Consensus Breadth (%)' + NL;
    const rows = tbody.querySelectorAll('tr:not([style*="display: none"])');

    rows.forEach(row => {
      const accession = row.getAttribute('data-accession') || '';
      const qc = getQcReads(sampleName);
      const rl = getAvgReadLen(sampleName, accession);
      const bg = getBackground(sampleName);
      let cons = getVal(sampleName, accession);
      if (cons !== null && cons > 100) cons = 100;
      const consTxt = (cons === null) ? '' : cons.toFixed(2);

      // Collect base Virasign cells only (skip injected Avg Read Length / Consensus).
      const out = [];
      row.querySelectorAll('td').forEach(td => {
        const col = td.getAttribute('data-col') || '';
        if (col === 'avg_read_length' || col === 'consensus_breadth_pct') return;
        let text = td.textContent.trim();
        text = text.replace(/📊/g, '').trim();
        if (text.includes(',') || text.includes('"')) {
          text = '"' + text.replace(/"/g, '""') + '"';
        }
        out.push(text);
      });

      // Prepend Sample + Background, insert QC after Segment, Avg Read Length after Mapped Reads.
      out.unshift(sampleName);
      out.splice(1, 0, bg);
      out.splice(7, 0, qc);
      // After QC: Mapped Reads is at index 8 → insert avg length at index 9.
      out.splice(9, 0, rl);
      out.push(consTxt);
      csv += out.join(',') + NL;
    });

    const blob = new Blob(['\ufeff' + csv], { type: 'text/csv;charset=utf-8;' });
    const link = document.createElement('a');
    link.href = URL.createObjectURL(blob);
    link.download = sampleName + '_results.csv';
    link.click();
  };

  // Override the all-samples CSV export to include Background + QC reads + per-hit avg read length + consensus breadth.
  // This does not change what is shown in the HTML tables; it only affects the downloaded file.
  if (typeof window.downloadAllSamplesCSV === 'function') {
    const origDownloadAll = window.downloadAllSamplesCSV;
    window.downloadAllSamplesCSV = function() {
      const NL = String.fromCharCode(10);
      let rows = [['Sample','Background','Accession','Organism','Viral Species','Nextclade Clade','Segment','QC reads','Mapped Reads (#)','Avg Read Length','Avg Identity (%)','Coverage Depth (x)','Coverage Breadth (%)','NOGR (#/%)','Z-score (species)','Z-score (genus)','Consensus Breadth (%)']];
      if (typeof allSamples === 'undefined' || typeof samplesData === 'undefined') return origDownloadAll();

      allSamples.forEach(sname => {
        const sdata = samplesData[sname];
        const qc = getQcReads(sname);
        const bg = getBackground(sname);
        if (!sdata) { rows.push([sname,bg,'','','','','',qc,'','','','','','','','','']); return; }
        let refs = [];
        Object.keys(sdata).forEach(db => { if (sdata[db].references) refs = refs.concat(sdata[db].references); });
        if (refs.length === 0) { rows.push([sname,bg,'','','','','',qc,'','','','','','','','','']); return; }
        refs.sort((a,b) => (b.coverage_breadth||0)-(a.coverage_breadth||0));
        refs.forEach(r => {
          const acc = r.accession||'';
          const cons = getVal(sname, acc);
          const rl = getAvgReadLen(sname, acc);
          const nb = Number(r.nogr_bases||r.non_overlapping_bases||0) || 0;
          const refLen = Number(r.ref_length || (r.coverage_profile && r.coverage_profile.ref_len) || 0) || 0;
          const nogrPct = refLen > 0 ? ((nb / refLen) * 100).toFixed(1) + '%' : '—';
          rows.push([
            sname,
            bg,
            acc,
            r.organism||'',
            r.viral_species||'',
            r.nextclade_clade||'',
            r.segment||'',
            qc,
            r.mapped_reads||0,
            rl,
            (r.avg_identity||0).toFixed(2),
            (r.coverage_depth||0).toFixed(2),
            ((r.coverage_breadth||0)*100).toFixed(1),
            String((r.nogr_regions||r.non_overlapping_reads||0)) + '|' + nogrPct,
            (function(){ const zs=(r.zscore_species!==undefined&&r.zscore_species!==null)?r.zscore_species:r.zscore; return (zs!==undefined&&zs!==null)?Number(zs).toFixed(2):''; })(),
            (r.zscore_genus !== undefined && r.zscore_genus !== null) ? Number(r.zscore_genus).toFixed(2) : '',
            (cons === null) ? '' : cons.toFixed(2)
          ]);
        });
      });
      const csv = rows.map(r => r.map(c => '"'+String(c).replace(/"/g,'""')+'"').join(',')).join(NL);
      const blob = new Blob([csv], {type:'text/csv'});
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = 'results_summary_all_samples.csv';
      a.click();
      URL.revokeObjectURL(url);
    };
  }

  // Base Virasign applyAllFilters / getFiltersFromSample index filters by DOM position.
  // Injected Avg Read Length (after Mapped Reads) and Consensus Breadth (trailing)
  // shift those indices by +1. Hide injected filter inputs (type=hidden) for the
  // duration of the base filter call so positional indices stay correct — without
  // removing DOM nodes (which steals focus after every keyup).
  function withBaseFilterInputsOnly(sampleName, fn){
    const filterRow = document.getElementById('filters-' + sampleName);
    // Capture caret BEFORE excluding injected inputs (type change / detach resets it to 0).
    const active = document.activeElement;
    let selStart = null;
    let selEnd = null;
    try {
      if (active && active.tagName === 'INPUT' && typeof active.selectionStart === 'number') {
        selStart = active.selectionStart;
        selEnd = active.selectionEnd;
      }
    } catch (e) {}

    // Detach only injected filter headers (not body cells — numeric filters use data-* attrs).
    const parked = [];
    if (filterRow) {
      Array.from(filterRow.querySelectorAll('th[data-col]')).forEach(th => {
        parked.push({ node: th, parent: th.parentNode, next: th.nextSibling });
        th.parentNode.removeChild(th);
      });
    }
    try {
      return fn();
    } finally {
      for (let i = parked.length - 1; i >= 0; i--) {
        const item = parked[i];
        if (!item.parent) continue;
        if (item.next && item.next.parentNode === item.parent) {
          item.parent.insertBefore(item.node, item.next);
        } else {
          item.parent.appendChild(item.node);
        }
      }
      if (active && typeof active.focus === 'function') {
        try {
          active.focus();
          if (selStart !== null && typeof active.setSelectionRange === 'function') {
            active.setSelectionRange(selStart, selEnd);
          }
        } catch (e) {}
      }
    }
  }

  // Heatmap / shared filter reader: map by placeholder, ignore injected columns.
  const origGetFiltersFromSample = window.getFiltersFromSample;
  if (typeof origGetFiltersFromSample === 'function'){
    window.getFiltersFromSample = function(sampleName){
      const filters = {
        minReads: null,
        minIdentity: null,
        minDepth: null,
        minBreadth: null,
        minNogr: null,
        minZscore: null,
        minZscoreGenus: null,
        filterAccession: '',
        filterOrganism: '',
        filterSpecies: '',
        filterClade: '',
        filterSegment: ''
      };
      const filterRow = document.getElementById('filters-' + sampleName);
      if (!filterRow) return filters;
      const byPh = {};
      filterRow.querySelectorAll('th:not([data-col]) input[type="text"]').forEach(inp => {
        byPh[inp.getAttribute('placeholder') || ''] = (inp.value || '').trim();
      });
      filters.filterAccession = (byPh['Accession'] || '').toLowerCase();
      filters.filterOrganism = (byPh['Organism'] || '').toLowerCase();
      filters.filterSpecies = (byPh['Species'] || '').toLowerCase();
      filters.filterClade = (byPh['Clade'] || '').toLowerCase();
      filters.filterSegment = (byPh['Segment'] || '').toLowerCase();
      const num = (ph) => {
        const raw = byPh[ph] || '';
        if (!raw) return null;
        const v = parseFloat(raw);
        return isNaN(v) ? null : v;
      };
      filters.minReads = num('Min Reads');
      filters.minIdentity = num('Min ID');
      filters.minDepth = num('Min Depth');
      filters.minBreadth = num('Min Breadth');
      filters.minNogr = num('Min NOGR');
      filters.minZscore = num('Min Z-sp');
      if (filters.minZscore === null) filters.minZscore = num('Min Z-score');
      filters.minZscoreGenus = num('Min Z-gen');
      return filters;
    };
  }

  // Extend filtering with consensus-breadth and avg-read-length rules when their filters are visible.
  const origApplyAllFilters = window.applyAllFilters;
  if (typeof origApplyAllFilters === 'function'){
    window.applyAllFilters = function(sampleName){
      withBaseFilterInputsOnly(sampleName, function(){
        origApplyAllFilters(sampleName);
      });
      try {
        const table = document.getElementById('table-' + sampleName);
        if (!table) return;
        const tbody = document.getElementById('tbody-' + sampleName);
        if (!tbody) return;

        const consTh = table.querySelector('th[data-col="consensus_breadth_pct"]');
        if (consTh && consTh.style.display !== 'none') {
          const input = consTh.querySelector('input[type="text"], input[type="hidden"]');
          const raw = input ? (input.value || '').trim() : '';
          if (raw !== '') {
            const minVal = parseFloat(raw);
            if (!isNaN(minVal)) {
              tbody.querySelectorAll('tr').forEach(row => {
                if (row.style.display === 'none') return;
                const vRaw = row.getAttribute('data-consensus-breadth') || '';
                const v = parseFloat(vRaw);
                if (isNaN(v) || v < minVal) row.style.display = 'none';
              });
            }
          }
        }

        const lenTh = table.querySelector('th[data-col="avg_read_length"]');
        if (lenTh) {
          const input = lenTh.querySelector('input[type="text"], input[type="hidden"]');
          const raw = input ? (input.value || '').trim() : '';
          if (raw !== '') {
            const minVal = parseFloat(raw);
            if (!isNaN(minVal)) {
              tbody.querySelectorAll('tr').forEach(row => {
                if (row.style.display === 'none') return;
                const vRaw = row.getAttribute('data-avg-read-length') || '';
                const v = parseFloat(vRaw);
                if (isNaN(v) || v < minVal) row.style.display = 'none';
              });
            }
          }
        }
      } catch (e) {}
    };
  }

  // Inject into the currently active sample (if already rendered).
  try {
    const active = document.querySelector('.sample-section.active');
    if (active && active.id && active.id.startsWith('sample-')){
      const sn = active.id.slice('sample-'.length);
      injectForSample(sn);
    }
  } catch (e) {}
})();
</script>
