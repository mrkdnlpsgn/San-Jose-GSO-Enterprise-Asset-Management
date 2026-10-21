// Prints / exports the LGU's Property Card: title block, PPE class, then one line for the receipt
// and one per transfer (Transfer = the person it went to, Office = where it went). Several cards
// print as one document, a page each, or as one workbook, a sheet each.

const ENTITY = 'SAN JOSE BATANGAS'
// The paper form has room for this many lines; shorter cards are padded with blank rows.
const FORM_ROWS = 14

const esc = (s) => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
const fmtDate = (d) =>
  d ? new Date(`${d}T00:00:00`).toLocaleDateString('en-PH', { year: 'numeric', month: '2-digit', day: '2-digit' }) : ''
const fmtMoney = (v) =>
  v != null && v !== '' ? '₱' + Number(v).toLocaleString('en-PH', { minimumFractionDigits: 2 }) : ''
const safeName = (s) => String(s).replace(/[:\\/?*[\]]/g, '-')

// Description cell lines: the receipt line also carries the amount, like the paper card.
function descriptionLines(card, e) {
  return e.kind === 'RECEIPT' ? [e.description, fmtMoney(card.unitValue)].filter(Boolean) : [e.description]
}

function cardHtml(card) {
  const rows = card.entries.map((e) => `<tr>
      <td class="c">${esc(fmtDate(e.date))}</td>
      <td class="c mono">${esc(e.reference)}</td>
      <td>${descriptionLines(card, e).map(esc).join('<br>')}</td>
      <td class="c">${e.receiptQty ?? ''}</td>
      <td class="c">${esc(e.transferTo)}</td>
      <td class="c">${esc(e.office)}</td>
      <td class="c">${e.balanceQty}</td>
    </tr>`).join('')
  const blanks = '<tr class="blank"><td></td><td></td><td></td><td></td><td></td><td></td><td></td></tr>'
    .repeat(Math.max(0, FORM_ROWS - card.entries.length))

  return `<section class="card">
  <table>
    <thead>
      <tr><th colspan="7" class="title">PROPERTY CARD</th></tr>
      <tr><th colspan="7" class="sub">${ENTITY}<br><span>LGU</span></th></tr>
      <tr class="meta">
        <th colspan="4" class="left">Plant, Property and Equipment: <u>${esc(card.category || '')}</u></th>
        <th colspan="3" class="left">Property Classification:</th>
      </tr>
      <tr class="cols">
        <th style="width:11%">Date</th><th style="width:15%">Reference Property #</th><th>Description</th>
        <th style="width:8%">Receipt Qty</th><th style="width:15%">Transfer</th><th style="width:17%">Office</th>
        <th style="width:8%">Balance Qty</th>
      </tr>
    </thead>
    <tbody>${rows}${blanks}</tbody>
  </table>
</section>`
}

// Opens the print window. Call it straight from a click: browsers block popups opened later.
export const openPrintWindow = () => window.open('', '_blank', 'width=1100,height=800')

// `win` lets a caller open the window on click and fill it once the card data has loaded.
export function printPropertyCards(cards, win = openPrintWindow()) {
  if (!win) throw new Error('The print window was blocked. Allow pop-ups for this site and try again.')
  const title = cards.length === 1 ? `Property Card ${cards[0].propertyNumber}` : `Property Cards (${cards.length})`
  const html = `<!DOCTYPE html>
<html>
<head>
  <title>${esc(title)}</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    :root { color-scheme: light; }
    body { font-family: Calibri, 'Segoe UI', Arial, sans-serif; font-size: 12px; padding: 28px; color: #000; background: #fff; }
    table { width: 100%; border-collapse: collapse; table-layout: fixed; }
    th, td { border: 1px solid #000; padding: 5px 6px; vertical-align: top; }
    th { font-weight: 700; }
    th.title { font-size: 18px; padding: 10px; letter-spacing: .04em; }
    th.sub { font-size: 13px; padding: 6px; }
    th.sub span { font-weight: 400; }
    tr.meta th { font-size: 12px; text-align: left; }
    tr.meta u { font-weight: 400; }
    tr.cols th { font-size: 12px; text-align: center; vertical-align: middle; }
    td.c { text-align: center; }
    td.mono { font-family: Consolas, monospace; font-size: 11px; }
    tr.blank td { height: 26px; }
    .card + .card { page-break-before: always; margin-top: 28px; }
    @media print { body { padding: 0; } .card + .card { margin-top: 0; } }
  </style>
</head>
<body>
  ${cards.map(cardHtml).join('\n')}
  <script>window.onload = () => { window.print(); window.onafterprint = () => window.close() }<\/script>
</body>
</html>`
  win.document.write(html)
  win.document.close()
}

export async function exportPropertyCardsExcel(cards) {
  const XLSX = await import('xlsx')
  const wb = XLSX.utils.book_new()
  const used = new Set()
  cards.forEach((card) => {
    const aoa = [
      ['PROPERTY CARD'],
      [ENTITY],
      ['LGU'],
      [`Plant, Property and Equipment: ${card.category || ''}`, '', '', '', 'Property Classification:'],
      ['Date', 'Reference Property #', 'Description', 'Receipt Qty', 'Transfer', 'Office', 'Balance Qty'],
      ...card.entries.map((e) => [
        e.date || '', e.reference || '', descriptionLines(card, e).join('\n'),
        e.receiptQty ?? '', e.transferTo || '', e.office || '', e.balanceQty,
      ]),
    ]
    const ws = XLSX.utils.aoa_to_sheet(aoa)
    ws['!cols'] = [{ wch: 12 }, { wch: 30 }, { wch: 44 }, { wch: 11 }, { wch: 26 }, { wch: 34 }, { wch: 11 }]
    ws['!merges'] = [0, 1, 2].map((r) => ({ s: { r, c: 0 }, e: { r, c: 6 } }))
      .concat([{ s: { r: 3, c: 0 }, e: { r: 3, c: 3 } }, { s: { r: 3, c: 4 }, e: { r: 3, c: 6 } }])
    let name = safeName(card.propertyNumber).slice(0, 31)
    for (let n = 2; used.has(name.toUpperCase()); n++) name = `${safeName(card.propertyNumber).slice(0, 27)} (${n})`
    used.add(name.toUpperCase())
    XLSX.utils.book_append_sheet(wb, ws, name)
  })
  const file = cards.length === 1 ? `Property_Card_${safeName(cards[0].propertyNumber)}` : `Property_Cards_${cards.length}`
  XLSX.writeFile(wb, `${file}_${new Date().toISOString().slice(0, 10)}.xlsx`)
}
