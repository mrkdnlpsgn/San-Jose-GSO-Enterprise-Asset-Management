// The GSO's Repair and Maintenance Card (Machineries & Equipment) for one asset: every approved
// maintenance record in date order, each with its parts (unit, quantity, unit cost, total) and its
// labor under "Labor:", and the record's cost of repair on its own line. Landscape long bond paper.

import { openPrintWindow } from './printWindow'
import { esc } from './printForm'

const money = (v) => (v == null || v === '' ? '' : Number(v).toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }))
const longDate = (d) => (d ? new Date(`${String(d).slice(0, 10)}T00:00:00`).toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: '2-digit' }) : '')
const qty = (v) => (v == null ? '' : Number(v).toLocaleString('en-PH', { maximumFractionDigits: 2 }))

const CSS = `
  * { box-sizing: border-box; margin: 0; padding: 0; }
  :root { color-scheme: light; }
  @page { size: 13in 8.5in; margin: 10mm 12mm; }
  body { font-family: Calibri, Arial, Helvetica, sans-serif; font-size: 11pt; color: #000; background: #fff; }
  .card { border: 1.5px solid #000; }
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
  @media screen { body { background: #e5e7eb; padding: 20px; } .card { background: #fff; max-width: 13in; margin: 0 auto; } }`

// records: the asset's maintenance records (with `items`); only approved ones are printed.
export function maintenanceCardHtml(asset, records) {
  const rows = records
    .filter((r) => !r.approvalStatus || r.approvalStatus === 'APPROVED')
    .sort((a, b) => String(a.maintenanceDate).localeCompare(String(b.maintenanceDate)) || a.id - b.id)
    .map((r) => {
      const items = r.items || []
      const parts = items.filter((i) => i.kind !== 'LABOR')
      const labor = items.filter((i) => i.kind === 'LABOR')
      return [
        `<tr><td class="date">${longDate(r.maintenanceDate)}</td><td colspan="5">${esc(r.actionsTaken || r.findings || '')}</td><td class="r">${money(r.cost)}</td></tr>`,
        ...parts.map((p) => `<tr><td></td><td class="item">${esc(p.particular)}</td><td class="c">${esc(p.unit || '')}</td><td class="c">${qty(p.quantity)}</td><td class="r">${money(p.unitCost)}</td><td class="r">${money(p.totalCost)}</td><td></td></tr>`),
        ...(labor.length ? [`<tr><td></td><td class="labor">Labor:</td><td></td><td></td><td></td><td></td><td></td></tr>`] : []),
        ...labor.map((l) => `<tr><td></td><td class="item">${esc(l.particular)}</td><td></td><td></td><td></td><td class="r">${money(l.totalCost)}</td><td></td></tr>`),
      ].join('\n')
    })
  // a few ruled blank lines at the end, for repairs written in by hand
  const blanks = Array.from({ length: 5 }, () => '<tr class="empty"><td></td><td></td><td></td><td></td><td></td><td></td><td></td></tr>').join('')

  return `<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>Repair and Maintenance Card ${esc(asset.propertyNumber)}</title><style>${CSS}</style></head>
<body>
  <div class="card">
    <div class="head">
      <h1>REPAIR AND MAINTENANCE CARD (MACHINERIES &amp; EQUIPMENT)</h1>
      <div class="row"><p>TYPE OF MACHINE / EQUIPMENT : <b>${esc(asset.description)}</b></p><p>ACQUISITION COST: <b>Php ${money(asset.unitValue)}</b></p></div>
      <div class="row"><p>PROPERTY NO. &nbsp;&nbsp;<b>${esc(asset.propertyNumber)}</b></p><p>DEPARTMENT : <b>${esc(asset.office?.officeName || '')}</b></p></div>
    </div>
    <table>
      <colgroup><col style="width:12%"><col style="width:36%"><col style="width:8%"><col style="width:8%"><col style="width:9%"><col style="width:9%"><col style="width:18%"></colgroup>
      <thead><tr><th>DATE OF REPAIR</th><th>PARTICULAR</th><th>UNIT</th><th>QUANTITY</th><th>UNIT COST</th><th>TOTAL COST</th><th>COST OF REPAIR</th></tr></thead>
      <tbody>
        ${rows.join('\n') || ''}
        ${blanks}
      </tbody>
    </table>
  </div>
  <script>window.onload = () => { window.print(); window.onafterprint = () => window.close() }<\/script>
</body></html>`
}

// `win` is a print window opened on the click (see openPrintWindow); pass it when the data loads after.
export function printMaintenanceCard(asset, records, win = openMaintenanceCardWindow()) {
  win.write(maintenanceCardHtml(asset, records))
}

export const openMaintenanceCardWindow = () => openPrintWindow({ width: 1200, height: 800, waiting: 'Preparing the maintenance card…' })
