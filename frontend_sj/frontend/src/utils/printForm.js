// The standard printed report format, taken from the GSO's RPCPPE: legal landscape, Times New
// Roman, a centred title block, a ruled table and page numbers at the bottom right. Every page
// holds ROWS_PER_PAGE rows of equal height that fill the rest of the page, under the title and
// table header; the signatures come at the bottom of each form's last page.

import { openPrintWindow } from './printWindow'

export const ROWS_PER_PAGE = 8

export const esc = (s) => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
export const longDate = (d) => (d ? new Date(`${d}T00:00:00`).toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' }) : '')

export function toPages(rows, size = ROWS_PER_PAGE) {
  const pages = []
  for (let i = 0; i < rows.length; i += size) pages.push(rows.slice(i, i + size))
  return pages.length ? pages : [[]]
}

// signers: [{ label: 'Certified Correct by:', caption: 'Signature over Printed Name of ...' }]
export function signaturesHtml(signers) {
  if (!signers?.length) return ''
  return `<div class="sign">
    ${signers.map((s) => `<div><p>${esc(s.label)}</p><p class="line"></p><p class="cap">${esc(s.caption)}</p></div>`).join('\n    ')}
  </div>`
}

const FORM_CSS = `
    * { box-sizing: border-box; margin: 0; padding: 0; }
    :root { color-scheme: light; }
    @page { size: legal landscape; margin: 12mm 12mm 14mm; @bottom-right { content: counter(page); font-family: 'Times New Roman', serif; font-size: 11pt; } }
    body { font-family: 'Times New Roman', Times, serif; font-size: 11pt; color: #000; background: #fff; padding: 20px; }
    .title { text-align: center; line-height: 1.3; }
    .title h1 { font-size: 13pt; font-weight: 700; }
    .title h2 { font-size: 12pt; font-weight: 700; }
    .fund { font-weight: 700; margin: 14px 0 8px; }
    .acct { text-indent: 3em; margin-bottom: 8px; }
    .title + table { margin-top: 14px; }
    table { width: 100%; border-collapse: collapse; table-layout: fixed; border: 2px solid #000; }
    /* a long heading wraps inside its column instead of running into the next one */
    th { font-size: 10pt; font-weight: 700; border: 1px solid #000; padding: 4px 3px; text-align: center; vertical-align: middle; overflow-wrap: anywhere; hyphens: auto; }
    td { font-size: calc(10.5pt * var(--fit, 1)); border: 1px solid #000; padding: 3px 4px; vertical-align: top; word-wrap: break-word; }
    thead { display: table-header-group; }
    tr { page-break-inside: avoid; }
    td.c { text-align: center; } td.r { text-align: right; white-space: nowrap; }
    td.rem { font-style: italic; }
    .dense th { font-size: 8.5pt; } .dense td { font-size: calc(9pt * var(--fit, 1)); }
    .sign { display: flex; gap: 32px; margin-top: 28px; page-break-inside: avoid; font-size: 10.5pt; }
    .sign > div { flex: 1; }
    .sign .line { border-bottom: 1px solid #000; height: 34px; }
    .sign .cap { text-align: center; font-size: 9pt; margin-top: 3px; }
    /* each form is exactly one printed page (legal landscape less the margins); the table takes
       whatever height the title block (and, on the last page, the signatures) leave */
    .form { width: 331mm; height: 189mm; display: flex; flex-direction: column; overflow: hidden; }
    .form > * { flex: none; }
    .form > .grow { flex: 1 1 auto; min-height: 0; }
    .form + .form { page-break-before: always; margin-top: 28px; }
    @media print { body { padding: 0; } .form + .form { margin-top: 0; } }`

// Runs in the print window before printing. Every page's rows get the height that makes
// ROWS_PER_PAGE of them fill the space under the title block, and a page with fewer rows is
// padded with blank ones - except a page carrying signatures (the last page of a form), whose
// table ends at its last row with the signatures right below it. Rows whose text needs more room
// grow, and the extra is taken back from the others; if a page still can't hold its rows, the
// table text is made smaller on every page (the same size throughout) until all of them fit, so
// no table ever runs off its page and loses its bottom rows and border.
const FILL_SCRIPT = `
  const PER = ${ROWS_PER_PAGE}
  const pages = [...document.querySelectorAll('section.form')].map((sec) => {
    const table = sec.querySelector('table'), body = table && table.tBodies[0]
    if (!body) return null
    const grow = document.createElement('div')
    grow.className = 'grow'
    table.replaceWith(grow)
    grow.appendChild(table)
    const sign = sec.querySelector('.sign')
    if (!sign) {
      const width = [...table.tHead.rows[0].cells].reduce((n, c) => n + c.colSpan, 0)
      while (body.rows.length < PER) {
        const tr = body.insertRow()
        for (let k = 0; k < width; k++) tr.insertCell()
      }
    }
    return { table, body, grow, sign }
  }).filter(Boolean)

  // lays one page out; true when its table fits on the page
  function layout({ table, body, grow, sign }) {
    const rows = [...body.rows]
    grow.style.flex = ''
    rows.forEach((tr) => { tr.style.height = '' })
    if (sign) sign.style.display = 'none'
    const head = table.tHead.offsetHeight
    // a few px spare for the 2px outer border and print rounding
    const room = () => grow.clientHeight - head - 6
    let rowH = Math.floor(room() / PER)
    let limit = room()
    if (sign) {
      sign.style.display = ''
      limit = room()
      rowH = Math.min(rowH, Math.floor(limit / rows.length))
      grow.style.flex = 'none'
    }
    rows.forEach((tr) => { tr.style.height = rowH + 'px' })
    for (let pass = 0; pass < 6; pass++) {
      const excess = table.offsetHeight - head - limit
      if (excess <= 0) break
      const flexible = rows.filter((tr) => tr.offsetHeight <= parseFloat(tr.style.height) + 1)
      if (!flexible.length) break
      const cut = Math.ceil(excess / flexible.length)
      flexible.forEach((tr) => { tr.style.height = Math.max(0, tr.offsetHeight - cut) + 'px' })
    }
    return table.offsetHeight - head <= limit + 1
  }

  for (let fit = 100; fit >= 60; fit -= 5) {
    document.body.style.setProperty('--fit', fit / 100)
    if (pages.map(layout).every(Boolean)) break
  }`

// Opens the print window. `forms` is one form's pages (each a <section class="form">), or a list
// of them - one per type of PPE, say; each form's signatures go at the bottom of its last page.
export function printForm(title, forms, signers) {
  const sign = signaturesHtml(signers)
  const body = (Array.isArray(forms) ? forms : [forms]).map((pagesHtml) => {
    const at = pagesHtml.lastIndexOf('</section>')
    return at < 0 ? pagesHtml + sign : pagesHtml.slice(0, at) + sign + pagesHtml.slice(at)
  }).join('\n')
  const html = `<!DOCTYPE html>
<html>
<head>
  <title>${esc(title)}</title>
  <style>${FORM_CSS}
  </style>
</head>
<body>
  ${body}
  <script>window.onload = () => {${FILL_SCRIPT}
  window.print(); window.onafterprint = () => window.close() }<\/script>
</body>
</html>`
  openPrintWindow({ width: 1200 }).write(html)
}
