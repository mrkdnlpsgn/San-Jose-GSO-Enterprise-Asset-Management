// Report on the Physical Count of Property, Plant and Equipment (RPCPPE), in the layout of the
// GSO's printed report: one form per type of PPE (category), each headed by the type, the
// "as at" date, the fund cluster and the accountability statement, then one row per item.

import { printForm, toPages, esc, longDate } from './printForm'

// xlsx is ~400 KB; load it only when someone exports
const loadXlsx = () => import('xlsx')

const money = (v) => Number(v).toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 })

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

// The printed form sets the officer and the date in bold.
const blank = '________________'
const accountabilityHtml = (s) =>
  `For which <b>${esc(s.officer || blank)}, ${esc(s.designation || blank)}, ${esc(s.entity || blank)}</b> is accountable, having assumed such accountability on <b>${esc(longDate(s.assumedOn) || blank)}</b>.`

// Column widths (%) measured from the GSO's printed form; a <colgroup> keeps them fixed on every page.
const COL_WIDTHS = [7, 8, 17, 11, 8, 10, 8, 8, 6, 6, 11]

const asAtText = (s) => `As at ${longDate(s.asAt) || longDate(new Date().toISOString().slice(0, 10))}`

// A longer type of PPE continues on further pages (see printForm.js).
function formHtml(group, s) {
  return toPages(group.rows).map((rows) => pageHtml(group, rows, s)).join('\n')
}

function pageHtml(group, rows, s) {
  const body = rows.map((a) => {
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
  <p class="acct">${accountabilityHtml(s)}</p>
  <table>
    <colgroup>${COL_WIDTHS.map((w) => `<col style="width:${w}%">`).join('')}</colgroup>
    <thead>
      <tr>
        <th rowspan="2">ARTICLE</th>
        <th rowspan="2">LOCATION</th>
        <th rowspan="2">DESCRIPTION</th>
        <th rowspan="2">PROPERTY NUMBER</th>
        <th rowspan="2">UNIT OF MEASURE</th>
        <th rowspan="2">UNIT VALUE</th>
        <th rowspan="2">QUANTITY per PROPERTY CARD</th>
        <th rowspan="2">QUANTITY per PHYSICAL COUNT</th>
        <th colspan="2">SHORTAGE/ OVERAGE</th>
        <th rowspan="2">REMARKS</th>
      </tr>
      <tr><th>Quantity</th><th>Value</th></tr>
    </thead>
    <tbody>${body}</tbody>
  </table>
</section>`
}

const RPCPPE_SIGNERS = [
  { label: 'Certified Correct by:', caption: 'Signature over Printed Name of Inventory Committee Chair and Members' },
  { label: 'Approved by:', caption: 'Signature over Printed Name of Head of Agency/Entity or Authorized Representative' },
  { label: 'Verified by:', caption: 'Signature over Printed Name of COA Representative' },
]

export function printRpcppe(groups, settings) {
  const s = { ...RPCPPE_DEFAULTS, ...settings }
  printForm(`RPCPPE ${asAtText(s)}`, groups.map((g) => formHtml(g, s)), RPCPPE_SIGNERS)
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
