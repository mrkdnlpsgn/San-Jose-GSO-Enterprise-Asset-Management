// Report on the Physical Count of Property, Plant and Equipment (RPCPPE), in the layout of the
// GSO's printed report: one form per type of PPE (category), each headed by the type, the
// "as at" date, the fund cluster and the accountability statement, then one row per item.

import { openPrintWindow } from './printWindow'

// xlsx is ~400 KB; load it only when someone exports
const loadXlsx = () => import('xlsx')

const esc = (s) => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
const money = (v) => Number(v).toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
const longDate = (d) => (d ? new Date(`${d}T00:00:00`).toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' }) : '')

export const RPCPPE_DEFAULTS = {
  asAt: '',
  fundCluster: 'General Fund',
  officer: 'REGIE B. AGNO',
  designation: 'Municipal General Services Officer',
  entity: 'Municipality of San Jose, Batangas',
  assumedOn: '2018-12-01',
}

// One report line per asset, in the form's column order.
export function rpcppeLine(a) {
  const so = Number(a.shortageOverageQty || 0)
  const soValue = Number(a.shortageOverageValue || 0)
  return {
    article: a.article?.articleName || '',
    location: a.office?.officeName || '',
    description: a.description || '',
    propertyNumber: a.propertyNumber || '',
    unit: 'unit',
    unitValue: a.unitValue != null ? Number(a.unitValue) : null,
    qtyCard: a.quantity ?? 1,
    qtyCount: a.physicalCount ?? '',
    // like the paper form, shortage/overage stays blank when nothing was found
    soQty: so ? so : '',
    soValue: so || soValue ? soValue : '',
    remarks: (a.condition || '').toLowerCase(),
  }
}

// Items on hand as at the report date, sorted the way the form lists them.
export function rpcppeRows(assets, asAt) {
  return assets
    .filter((a) => !asAt || !a.acquisitionDate || a.acquisitionDate <= asAt)
    .slice()
    .sort((x, y) =>
      (x.article?.articleName || '￿').localeCompare(y.article?.articleName || '￿')
      || (x.office?.officeName || '').localeCompare(y.office?.officeName || '')
      || (x.propertyNumber || '').localeCompare(y.propertyNumber || ''))
}

const accountability = (s) =>
  `For which ${s.officer || '________________'}, ${s.designation || '________________'}, ${s.entity || '________________'} is accountable, having assumed such accountability on ${longDate(s.assumedOn) || '________________'}.`

const asAtText = (s) => `As at ${longDate(s.asAt) || longDate(new Date().toISOString().slice(0, 10))}`

function formHtml(group, s) {
  const body = group.rows.map((a) => {
    const l = rpcppeLine(a)
    return `<tr>
      <td>${esc(l.article)}</td><td>${esc(l.location)}</td><td>${esc(l.description)}</td>
      <td class="c">${esc(l.propertyNumber)}</td><td class="c">${l.unit}</td>
      <td class="r">${l.unitValue != null ? money(l.unitValue) : ''}</td>
      <td class="c">${esc(l.qtyCard)}</td><td class="c">${esc(l.qtyCount)}</td>
      <td class="c">${esc(l.soQty)}</td><td class="r">${l.soValue !== '' ? money(l.soValue) : ''}</td>
      <td class="rem">${esc(l.remarks)}</td>
    </tr>`
  }).join('')

  return `<section class="form">
  <div class="title">
    <h1>REPORT ON THE PHYSICAL COUNT OF PROPERTY, PLANT AND EQUIPMENT</h1>
    <h2>${esc(group.categoryName.toUpperCase())}</h2>
    <p>(Type of Property, Plant and Equipment)</p>
    <p>${esc(asAtText(s))}</p>
  </div>
  <p class="fund">Fund Cluster : ${esc((s.fundCluster || '').toUpperCase())}</p>
  <p class="acct">${esc(accountability(s))}</p>
  <table>
    <thead>
      <tr>
        <th rowspan="2" style="width:9%">ARTICLE</th>
        <th rowspan="2" style="width:9%">LOCATION</th>
        <th rowspan="2" style="width:16%">DESCRIPTION</th>
        <th rowspan="2" style="width:12%">PROPERTY NUMBER</th>
        <th rowspan="2" style="width:7%">UNIT OF MEASURE</th>
        <th rowspan="2" style="width:9%">UNIT VALUE</th>
        <th rowspan="2" style="width:7%">QUANTITY per PROPERTY CARD</th>
        <th rowspan="2" style="width:7%">QUANTITY per PHYSICAL COUNT</th>
        <th colspan="2">SHORTAGE/ OVERAGE</th>
        <th rowspan="2" style="width:9%">REMARKS</th>
      </tr>
      <tr><th style="width:6%">Quantity</th><th style="width:7%">Value</th></tr>
    </thead>
    <tbody>${body}</tbody>
  </table>
  <div class="sign">
    <div><p>Certified Correct by:</p><p class="line"></p><p class="cap">Signature over Printed Name of Inventory Committee Chair and Members</p></div>
    <div><p>Approved by:</p><p class="line"></p><p class="cap">Signature over Printed Name of Head of Agency/Entity or Authorized Representative</p></div>
    <div><p>Verified by:</p><p class="line"></p><p class="cap">Signature over Printed Name of COA Representative</p></div>
  </div>
</section>`
}

export function printRpcppe(groups, settings) {
  const s = { ...RPCPPE_DEFAULTS, ...settings }
  const html = `<!DOCTYPE html>
<html>
<head>
  <title>RPCPPE ${esc(asAtText(s))}</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    :root { color-scheme: light; }
    @page { size: legal landscape; margin: 12mm 12mm 14mm; @bottom-right { content: counter(page); font-family: 'Times New Roman', serif; font-size: 11pt; } }
    body { font-family: 'Times New Roman', Times, serif; font-size: 11pt; color: #000; background: #fff; padding: 20px; }
    .title { text-align: center; line-height: 1.3; }
    .title h1 { font-size: 13pt; font-weight: 700; }
    .title h2 { font-size: 12pt; font-weight: 700; }
    .fund { font-weight: 700; margin: 14px 0 8px; }
    .acct { text-indent: 3em; margin-bottom: 8px; }
    table { width: 100%; border-collapse: collapse; table-layout: fixed; border: 2px solid #000; }
    th { font-size: 10pt; font-weight: 700; border: 1px solid #000; padding: 4px 3px; text-align: center; vertical-align: middle; }
    td { font-size: 10.5pt; border: 1px solid #000; padding: 3px 4px; vertical-align: top; word-wrap: break-word; }
    thead { display: table-header-group; }
    tr { page-break-inside: avoid; }
    td.c { text-align: center; } td.r { text-align: right; white-space: nowrap; }
    td.rem { font-style: italic; }
    .sign { display: flex; gap: 32px; margin-top: 28px; page-break-inside: avoid; font-size: 10.5pt; }
    .sign > div { flex: 1; }
    .sign .line { border-bottom: 1px solid #000; height: 34px; }
    .sign .cap { text-align: center; font-size: 9pt; margin-top: 3px; }
    .form + .form { page-break-before: always; margin-top: 28px; }
    @media print { body { padding: 0; } .form + .form { margin-top: 0; } }
  </style>
</head>
<body>
  ${groups.map((g) => formHtml(g, s)).join('\n')}
  <script>window.onload = () => { window.print(); window.onafterprint = () => window.close() }<\/script>
</body>
</html>`
  openPrintWindow({ width: 1200 }).write(html)
}

// One sheet per type of PPE in a single workbook.
export async function exportRpcppeExcel(groups, settings) {
  const s = { ...RPCPPE_DEFAULTS, ...settings }
  const XLSX = await loadXlsx()
  const wb = XLSX.utils.book_new()
  const used = new Set()
  groups.forEach((g) => {
    const aoa = [
      ['REPORT ON THE PHYSICAL COUNT OF PROPERTY, PLANT AND EQUIPMENT'],
      [g.categoryName.toUpperCase()],
      ['(Type of Property, Plant and Equipment)'],
      [asAtText(s)],
      [],
      [`Fund Cluster : ${(s.fundCluster || '').toUpperCase()}`],
      [accountability(s)],
      [],
      ['ARTICLE', 'LOCATION', 'DESCRIPTION', 'PROPERTY NUMBER', 'UNIT OF MEASURE', 'UNIT VALUE',
        'QUANTITY per PROPERTY CARD', 'QUANTITY per PHYSICAL COUNT', 'SHORTAGE/OVERAGE', '', 'REMARKS'],
      ['', '', '', '', '', '', '', '', 'Quantity', 'Value', ''],
    ]
    g.rows.forEach((a) => {
      const l = rpcppeLine(a)
      aoa.push([l.article, l.location, l.description, l.propertyNumber, l.unit,
        l.unitValue != null ? Number(l.unitValue.toFixed(2)) : '', l.qtyCard, l.qtyCount,
        l.soQty, l.soValue !== '' ? Number(Number(l.soValue).toFixed(2)) : '', l.remarks])
    })
    aoa.push([], ['Certified Correct by:', '', '', '', 'Approved by:', '', '', '', 'Verified by:'], [], [],
      ['Signature over Printed Name of Inventory Committee Chair and Members', '', '', '',
        'Signature over Printed Name of Head of Agency/Entity or Authorized Representative', '', '', '',
        'Signature over Printed Name of COA Representative'])

    const ws = XLSX.utils.aoa_to_sheet(aoa)
    ws['!cols'] = [14, 16, 30, 20, 10, 14, 12, 12, 10, 12, 14].map((wch) => ({ wch }))
    const full = (r) => ({ s: { r, c: 0 }, e: { r, c: 10 } })
    ws['!merges'] = [full(0), full(1), full(2), full(3), full(5), full(6),
      ...[0, 1, 2, 3, 4, 5, 6, 7, 10].map((c) => ({ s: { r: 8, c }, e: { r: 9, c } })),
      { s: { r: 8, c: 8 }, e: { r: 8, c: 9 } }]
    const valueFmt = '#,##0.00'
    for (let r = 10; r < 10 + g.rows.length; r++) {
      for (const c of [5, 9]) {
        const cell = ws[XLSX.utils.encode_cell({ r, c })]
        if (cell && cell.t === 'n') cell.z = valueFmt
      }
    }

    let name = g.categoryName.replace(/[:\\/?*[\]]/g, '-').slice(0, 31)
    for (let n = 2; used.has(name.toUpperCase()); n++) name = `${name.slice(0, 27)} (${n})`
    used.add(name.toUpperCase())
    XLSX.utils.book_append_sheet(wb, ws, name)
  })
  const stamp = s.asAt || new Date().toISOString().slice(0, 10)
  XLSX.writeFile(wb, `RPCPPE_${groups.length === 1 ? groups[0].categoryName.replace(/[^A-Za-z0-9]+/g, '_') + '_' : ''}${stamp}.xlsx`)
}
