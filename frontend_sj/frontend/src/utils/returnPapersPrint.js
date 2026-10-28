// The two papers made when an asset changes end user: the Property Return Slip (LGU Form No. 12,
// copied from the GSO's printed form) and the new Property Acknowledgement Receipt. Both print on
// long bond paper, portrait, with the municipal seal on top. `officer` is who signs for the GSO
// (receives the return, issues the PAR): { name, position }.

import { openPrintWindow } from './printWindow'
import { esc } from './printForm'

export const PAPERS_OFFICER_DEFAULTS = { name: 'REGIE B. AGNO', position: 'MGDH I (MGSO)' }

const shortDate = (d) => {
  if (!d) return ''
  const [y, m, day] = String(d).slice(0, 10).split('-')
  return `${m}/${day}/${y}`
}
const money = (v) => (v == null ? '' : Number(v).toLocaleString('en-PH', { minimumFractionDigits: 2, maximumFractionDigits: 2 }))
const ordinal = (n) => {
  const s = ['th', 'st', 'nd', 'rd'], v = n % 100
  return n + (s[(v - 20) % 10] || s[v] || s[0])
}
const dayParts = (d) => {
  const date = new Date(`${String(d).slice(0, 10)}T00:00:00`)
  return { day: ordinal(date.getDate()), month: date.toLocaleDateString('en-US', { month: 'long' }), year: date.getFullYear() }
}

// description on the first line, then the specifications as they were typed (one per line)
const describe = (p) => `<b>${esc(p.description)}</b>${p.specifications
  ? `<div class="specs">${esc(p.specifications).replace(/\r?\n/g, '<br>')}</div>` : ''}`

const CSS = `
  * { box-sizing: border-box; margin: 0; padding: 0; }
  :root { color-scheme: light; }
  @page { size: 8.5in 13in; margin: 12mm 14mm; }
  body { font-family: Calibri, Arial, Helvetica, sans-serif; font-size: 11pt; color: #000; background: #fff; }
  .page { width: 100%; height: calc(13in - 24mm); display: flex; flex-direction: column; }
  .form-no { font-size: 9.5pt; font-weight: 700; }
  .head { text-align: center; line-height: 1.35; margin-top: 4px; }
  .head img { width: 70px; height: 70px; display: block; margin: 0 auto 6px; }
  .head .muni { font-weight: 700; }
  .head h1 { font-size: 12pt; font-weight: 700; margin-top: 12px; letter-spacing: 0.02em; }
  .meta { margin-top: 14px; line-height: 1.6; }
  .meta b { text-transform: uppercase; }
  .meta .row { display: flex; justify-content: space-between; gap: 16px; }
  .grow { flex: 1 1 auto; display: flex; flex-direction: column; min-height: 0; margin-top: 4px; }
  table { width: 100%; border-collapse: collapse; table-layout: fixed; border: 1.5px solid #000; }
  th { font-size: 9.5pt; font-weight: 700; border: 1px solid #000; padding: 5px 3px; text-align: center; vertical-align: middle; }
  td { font-size: 10pt; border-left: 1px solid #000; border-right: 1px solid #000; padding: 6px 4px; vertical-align: top; word-wrap: break-word; }
  td.c { text-align: center; } td.r { text-align: right; white-space: nowrap; } td.nw { white-space: nowrap; }
  .items { flex: 1 1 auto; height: 100%; }
  .items tbody tr.fill td { height: 100%; }
  .specs { margin-top: 4px; line-height: 1.35; }
  .cert { border: 1.5px solid #000; border-top: none; }
  .cert h2 { font-size: 10.5pt; font-weight: 700; text-align: center; padding: 6px; border-bottom: 1px solid #000; }
  .cert .cols { display: flex; }
  .cert .cols > div { flex: 1; padding: 10px 12px 14px; line-height: 1.5; }
  .cert .cols > div + div { border-left: 1px solid #000; }
  .cert u { padding: 0 6px; }
  .sig { text-align: center; margin-top: 34px; line-height: 1.3; }
  .sig .name { font-weight: 700; text-transform: uppercase; border-top: 1px solid #000; display: inline-block; min-width: 70%; padding-top: 2px; }
  .label { font-weight: 700; }
  @media screen { body { background: #e5e7eb; padding: 20px; } .page { background: #fff; width: 8.5in; margin: 0 auto; padding: 12mm 14mm; height: 13in; } }`

function head(title, formNo) {
  return `${formNo ? `<p class="form-no">${esc(formNo)}</p>` : ''}
  <div class="head">
    <img src="${window.location.origin}/logo.webp" alt="" />
    <p>Republic of the Philippines</p>
    <p class="muni">MUNICIPALITY OF SAN JOSE</p>
    <h1>${esc(title)}</h1>
  </div>`
}

function open(title, body) {
  openPrintWindow({ width: 900, height: 1000, waiting: 'Preparing the form…' }).write(`<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>${esc(title)}</title><style>${CSS}</style></head>
<body><div class="page">${body}</div>
<script>window.onload = () => { window.print(); window.onafterprint = () => window.close() }<\/script>
</body></html>`)
}

const PURPOSES = [['DISPOSAL', 'Disposal'], ['REPAIR', 'Repair'], ['RETURNED_TO_STOCK', 'Returned to Stock'], ['UNSERVICEABLE', 'Unserviceable']]

export function printReturnSlip(slip, officer = PAPERS_OFFICER_DEFAULTS) {
  const { day, month, year } = dayParts(slip.returnDate)
  const person = slip.returnedByName || ''
  const purpose = PURPOSES.map(([k, label]) => `( ${slip.purpose === k ? 'X' : '&nbsp;&nbsp;'} ) ${label}`).join('&nbsp;&nbsp;&nbsp;&nbsp;')
  open(`Property Return Slip ${slip.slipNumber}`, `
  ${head('PROPERTY RETURN SLIP', 'LGU FORM NO. 12')}
  <div class="meta">
    <div class="row"><p>NAME OF OFFICE: <b>${esc(slip.officeName || '')}</b></p><p>No. <b>${esc(slip.slipNumber)}</b></p></div>
    <p>PURPOSE &nbsp;: ${purpose}</p>
  </div>
  <div class="grow">
    <table class="items">
      <colgroup><col style="width:5%"><col style="width:6%"><col style="width:26%"><col style="width:15%"><col style="width:11%"><col style="width:12%"><col style="width:13.5%"><col style="width:11.5%"></colgroup>
      <thead><tr><th>QTY</th><th>UNIT</th><th>DESCRIPTION</th><th>PROPERTY NUMBER</th><th>DATE ACQUIRED</th><th>NAME OF END-USER</th><th>UNIT VALUE</th><th>TOTAL VALUE</th></tr></thead>
      <tbody><tr class="fill">
        <td class="c">1</td><td class="c">Unit</td><td>${describe(slip)}</td>
        <td class="c">${esc(slip.propertyNumber)}${slip.parNumber ? `<br><br>PAR No.<br>${esc(slip.parNumber)}` : ''}</td>
        <td class="c nw">${shortDate(slip.acquisitionDate)}</td><td class="c">${esc(person.toUpperCase())}</td>
        <td class="r">${slip.unitValue != null ? `PHP ${money(slip.unitValue)}` : ''}</td><td class="r">${money(slip.unitValue)}</td>
      </tr></tbody>
    </table>
  </div>
  <div class="cert">
    <h2>CERTIFICATION</h2>
    <div class="cols">
      <div>
        <p>I HEREBY CERTIFY that I have this <u>${day}</u> day of <u>${month}</u>, ${year} returned to ${esc(officer.name)} MGSO the items / articles described above.</p>
        <div class="sig"><p class="name">${esc(person)}</p><p>${esc(slip.returnedByPosition || '')}</p></div>
      </div>
      <div>
        <p>I HEREBY CERTIFY that I have this <u>${day}</u> day of <u>${month}</u>, ${year} RECEIVED from ${esc(person)} the items / articles described above.</p>
        <div class="sig"><p class="name">${esc(officer.name)}</p><p>${esc(officer.position)}</p></div>
      </div>
    </div>
  </div>`)
}

export function printPar(par, officer = PAPERS_OFFICER_DEFAULTS) {
  open(`PAR ${par.parNumber}`, `
  ${head('PROPERTY ACKNOWLEDGEMENT RECEIPT')}
  <div class="meta">
    <div class="row"><p>Entity Name: <b>Municipality of San Jose, Batangas</b></p><p>PAR No.: <b>${esc(par.parNumber)}</b></p></div>
    <div class="row"><p>Office: <b>${esc(par.officeName || '')}</b></p><p>Fund Cluster: ________________</p></div>
  </div>
  <div class="grow">
    <table class="items">
      <colgroup><col style="width:8%"><col style="width:8%"><col style="width:38%"><col style="width:18%"><col style="width:13%"><col style="width:15%"></colgroup>
      <thead><tr><th>Quantity</th><th>Unit</th><th>Description</th><th>Property Number</th><th>Date Acquired</th><th>Amount</th></tr></thead>
      <tbody><tr class="fill">
        <td class="c">1</td><td class="c">Unit</td><td>${describe(par)}</td>
        <td class="c">${esc(par.propertyNumber)}</td><td class="c">${shortDate(par.acquisitionDate)}</td>
        <td class="r">${par.unitValue != null ? `PHP ${money(par.unitValue)}` : ''}</td>
      </tr></tbody>
    </table>
  </div>
  <div class="cert">
    <div class="cols">
      <div>
        <p class="label">Received by:</p>
        <div class="sig"><p class="name">${esc(par.personnelName || '')}</p><p>Signature over Printed Name of End User</p>
          <p style="margin-top:10px">${esc(par.personnelPosition || '')}${par.personnelPosition && par.officeName ? ', ' : ''}${esc(par.officeName || '')}</p><p>Position / Office</p>
          <p style="margin-top:10px">${shortDate(par.issueDate)}</p><p>Date</p></div>
      </div>
      <div>
        <p class="label">Issued by:</p>
        <div class="sig"><p class="name">${esc(officer.name)}</p><p>Signature over Printed Name of Supply and/or Property Custodian</p>
          <p style="margin-top:10px">${esc(officer.position)}</p><p>Position / Office</p>
          <p style="margin-top:10px">${shortDate(par.issueDate)}</p><p>Date</p></div>
      </div>
    </div>
  </div>`)
}
