// The GSO's Repair and Maintenance Card (Machineries & Equipment), one per asset: every approved
// maintenance record in date order, each with its parts (unit, quantity, unit cost, total) and its
// labor under "Labor:", and the record's cost of repair on its own line. Printed on landscape long
// bond paper, one card per page, or exported to Excel, one sheet per card. Reports page's
// "Repair and Maintenance Card" and the Maintenance pages print from here.

import { openPrintWindow } from './printWindow'
import { esc } from './printForm'

export const TITLE = 'REPAIR AND MAINTENANCE CARD (MACHINERIES & EQUIPMENT)'
const money = (v) => (v == null || v === '' ? '' : Number(v).toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }))
export const repairDate = (d) => (d ? new Date(`${String(d).slice(0, 10)}T00:00:00`).toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: '2-digit' }) : '')
const qty = (v) => (v == null ? '' : Number(v).toLocaleString('en-PH', { maximumFractionDigits: 2 }))
// A repair goes on the card once it is approved and something was done: it is completed, or it
// has a cost or parts and labor. The placeholder opened when an asset is marked repairable
// ("Pending review and assignment", no cost) stays off until the repair is recorded.
const isCounted = (r) => (!r.approvalStatus || r.approvalStatus === 'APPROVED')
  && (r.status === 'COMPLETED' || r.cost != null || (r.items || []).length > 0)
const byDate = (a, b) => String(a.maintenanceDate).localeCompare(String(b.maintenanceDate)) || a.id - b.id

// A card's lines, top to bottom: each repair, then its parts, "Labor:" and the labor. Every line
// has the card's seven columns (blank where the paper leaves them blank).
export function cardLines(records) {
  return records.filter(isCounted).sort(byDate).flatMap((r) => {
    const items = r.items || []
    const parts = items.filter((i) => i.kind !== 'LABOR')
    const labor = items.filter((i) => i.kind === 'LABOR')
    const blank = { date: '', particular: '', unit: '', quantity: '', unitCost: '', total: '', cost: '' }
    return [
      { ...blank, kind: 'repair', date: repairDate(r.maintenanceDate), particular: r.actionsTaken || r.findings || '', cost: money(r.cost) },
      ...parts.map((p) => ({ ...blank, kind: 'part', particular: p.particular, unit: p.unit || '', quantity: qty(p.quantity), unitCost: money(p.unitCost), total: money(p.totalCost) })),
      ...(labor.length ? [{ ...blank, kind: 'laborHead', particular: 'Labor:' }] : []),
      ...labor.map((l) => ({ ...blank, kind: 'labor', particular: l.particular, total: money(l.totalCost) })),
    ]
  })
}

// One card per asset that has approved maintenance. `assets` (optional) fills in the acquisition
// cost and department, which maintenance records don't carry.
export function maintenanceCardsOf(records, assets = []) {
  const assetById = new Map(assets.map((a) => [a.id, a]))
  const byAsset = new Map()
  records.filter((r) => isCounted(r) && r.asset?.id).forEach((r) => {
    if (!byAsset.has(r.asset.id)) byAsset.set(r.asset.id, [])
    byAsset.get(r.asset.id).push(r)
  })
  return [...byAsset.entries()].map(([id, recs]) => {
    const asset = { ...recs[0].asset, ...(assetById.get(id) || {}) }
    const sorted = [...recs].sort(byDate)
    return {
      key: String(id),
      asset,
      records: sorted,
      repairs: sorted.length,
      totalCost: sorted.reduce((t, r) => t + Number(r.cost || 0), 0),
      lastRepair: sorted[sorted.length - 1].maintenanceDate,
    }
  }).sort((a, b) => String(b.lastRepair).localeCompare(String(a.lastRepair)))
}

const CSS = `
  * { box-sizing: border-box; margin: 0; padding: 0; }
  :root { color-scheme: light; }
  @page { size: 13in 8.5in; margin: 10mm 12mm; }
  body { font-family: Calibri, Arial, Helvetica, sans-serif; font-size: 11pt; color: #000; background: #fff; }
  .card { border: 1.5px solid #000; }
  .card + .card { page-break-before: always; break-before: page; }
  /* one printed page: landscape long bond less the margins (the fill script rules lines down to it) */
  :root { --page: 195.9mm; }
  .head { padding: 8px 12px 10px; border-bottom: 1.5px solid #000; }
  .head h1 { font-size: 13pt; font-weight: 700; text-align: center; margin-bottom: 8px; }
  .head .row { display: flex; justify-content: space-between; gap: 24px; line-height: 1.5; }
  .head b { font-weight: 700; }
  table { width: 100%; border-collapse: collapse; table-layout: fixed; }
  th { font-size: 10.5pt; font-weight: 700; border: 1px solid #000; padding: 5px 4px; text-align: center; vertical-align: middle; }
  th:first-child, td:first-child { border-left: none; } th:last-child, td:last-child { border-right: none; }
  td { font-size: 10.5pt; border: 1px solid #000; padding: 3px 6px; vertical-align: top; }
  thead { display: table-header-group; }
  tr { page-break-inside: avoid; }
  td.c { text-align: center; } td.r { text-align: right; white-space: nowrap; }
  td.date { text-align: center; white-space: nowrap; }
  td.item { padding-left: 14px; }
  td.labor { font-style: italic; padding-left: 14px; }
  .empty td { height: 22px; }
  @media screen { body { background: #e5e7eb; padding: 20px; } .card { background: #fff; max-width: 13in; margin: 0 auto 20px; } }`

function cardHtml({ asset, records }) {
  const rows = cardLines(records).map((l) => (l.kind === 'repair'
    ? `<tr><td class="date">${l.date}</td><td colspan="5">${esc(l.particular)}</td><td class="r">${l.cost}</td></tr>`
    : `<tr><td></td><td class="${l.kind === 'laborHead' ? 'labor' : 'item'}">${esc(l.particular)}</td><td class="c">${esc(l.unit)}</td><td class="c">${l.quantity}</td><td class="r">${l.unitCost}</td><td class="r">${l.total}</td><td></td></tr>`))
  // ruled blank lines for repairs written in by hand; the fill script adds more, down to the page bottom
  const blanks = Array.from({ length: 3 }, () => '<tr class="empty"><td></td><td></td><td></td><td></td><td></td><td></td><td></td></tr>').join('')
  return `<div class="card">
    <div class="head">
      <h1>${esc(TITLE)}</h1>
      <div class="row"><p>TYPE OF MACHINE / EQUIPMENT : <b>${esc(asset.description)}</b></p><p>ACQUISITION COST: <b>Php ${money(asset.unitValue)}</b></p></div>
      <div class="row"><p>PROPERTY NO. &nbsp;&nbsp;<b>${esc(asset.propertyNumber)}</b></p><p>DEPARTMENT : <b>${esc(asset.office?.officeName || '')}</b></p></div>
    </div>
    <table>
      <colgroup><col style="width:12%"><col style="width:36%"><col style="width:8%"><col style="width:8%"><col style="width:9%"><col style="width:9%"><col style="width:18%"></colgroup>
      <thead><tr><th>DATE OF REPAIR</th><th>PARTICULAR</th><th>UNIT</th><th>QUANTITY</th><th>UNIT COST</th><th>TOTAL COST</th><th>COST OF REPAIR</th></tr></thead>
      <tbody>
        ${rows.join('\n')}
        ${blanks}
      </tbody>
    </table>
  </div>`
}

// cards: [{ asset, records }] (records with their `items`; only approved ones are printed).
export function maintenanceCardsHtml(cards) {
  const title = cards.length === 1 ? `Repair and Maintenance Card ${cards[0].asset.propertyNumber}` : `Repair and Maintenance Cards (${cards.length})`
  return `<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>${esc(title)}</title><style>${CSS}</style></head>
<body>
  ${cards.map(cardHtml).join('\n')}
  <script>window.onload = () => {
    // like the paper card, the ruled lines run down to the bottom of each card's last page
    const page = document.createElement('div')
    page.style.height = 'var(--page)'
    document.body.appendChild(page)
    const pageH = page.offsetHeight
    page.remove()
    document.querySelectorAll('.card').forEach((card) => {
      const body = card.querySelector('tbody'), proto = body.querySelector('tr.empty')
      if (!proto) return
      const rowH = proto.offsetHeight
      const used = card.offsetHeight % pageH || pageH
      for (let n = Math.floor((pageH - used - 4) / rowH); n > 0; n--) body.appendChild(proto.cloneNode(true))
    })
    window.print(); window.onafterprint = () => window.close()
  }<\/script>
</body></html>`
}

export const openMaintenanceCardWindow = () => openPrintWindow({ width: 1200, height: 800, waiting: 'Preparing the maintenance card…' })

// `win` is a print window opened on the click (see openPrintWindow); pass it when the data loads after.
export function printMaintenanceCards(cards, win = openMaintenanceCardWindow()) {
  win.write(maintenanceCardsHtml(cards))
}

export function printMaintenanceCard(asset, records, win) {
  printMaintenanceCards([{ asset, records }], win)
}

const safeName = (s) => String(s || 'card').replace(/[\\/?*[\]:]/g, '-')

// One sheet per card, laid out like the paper: title, the four header details, then the table.
export async function exportMaintenanceCardsExcel(cards) {
  const XLSX = await import('xlsx')
  const wb = XLSX.utils.book_new()
  const used = new Set()
  cards.forEach(({ asset, records }) => {
    const aoa = [
      [TITLE],
      [`TYPE OF MACHINE / EQUIPMENT : ${asset.description || ''}`, '', '', '', '', `ACQUISITION COST: Php ${money(asset.unitValue)}`],
      [`PROPERTY NO. ${asset.propertyNumber || ''}`, '', '', '', '', `DEPARTMENT : ${asset.office?.officeName || ''}`],
      ['DATE OF REPAIR', 'PARTICULAR', 'UNIT', 'QUANTITY', 'UNIT COST', 'TOTAL COST', 'COST OF REPAIR'],
      ...cardLines(records).map((l) => [l.date, l.particular, l.unit, l.quantity, l.unitCost, l.total, l.cost]),
    ]
    const ws = XLSX.utils.aoa_to_sheet(aoa)
    ws['!cols'] = [{ wch: 20 }, { wch: 48 }, { wch: 9 }, { wch: 10 }, { wch: 13 }, { wch: 13 }, { wch: 18 }]
    ws['!merges'] = [
      { s: { r: 0, c: 0 }, e: { r: 0, c: 6 } },
      { s: { r: 1, c: 0 }, e: { r: 1, c: 4 } }, { s: { r: 1, c: 5 }, e: { r: 1, c: 6 } },
      { s: { r: 2, c: 0 }, e: { r: 2, c: 4 } }, { s: { r: 2, c: 5 }, e: { r: 2, c: 6 } },
    ]
    let name = safeName(asset.propertyNumber).slice(0, 31)
    for (let n = 2; used.has(name.toUpperCase()); n++) name = `${safeName(asset.propertyNumber).slice(0, 27)} (${n})`
    used.add(name.toUpperCase())
    XLSX.utils.book_append_sheet(wb, ws, name)
  })
  const file = cards.length === 1 ? `Repair_Maintenance_Card_${safeName(cards[0].asset.propertyNumber)}` : `Repair_Maintenance_Cards_${cards.length}`
  XLSX.writeFile(wb, `${file}_${new Date().toISOString().slice(0, 10)}.xlsx`)
}
