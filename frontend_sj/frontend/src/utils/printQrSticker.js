import { escapeHtml } from './helpers'
import { openPrintWindow as openWindow } from './printWindow'

// Prints one 30 × 30 mm asset QR sticker: the QR code with the municipal seal in the
// middle and the property number under it. `@page` sets the paper to the sticker itself,
// so a label printer puts one tag per label. The QR codes use error-correction level H,
// which still reads with the middle covered; the seal is kept to 24% of the QR's width
// (about 6% of its area) to stay well inside that.
const STICKER_STYLES = `
  @page { size: 30mm 30mm; margin: 0; }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  html, body { width: 30mm; height: 30mm; }
  body { font-family: Arial, Helvetica, sans-serif; color: #000; background: #fff;
         -webkit-print-color-adjust: exact; print-color-adjust: exact; }
  .label { width: 30mm; height: 30mm; padding: 1.5mm; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 0.6mm; overflow: hidden; }
  .qr { position: relative; flex: none; width: 22.5mm; height: 22.5mm; }
  .qr > img, .qr > svg { display: block; width: 100%; height: 100%; }
  .qr .seal { position: absolute; top: 50%; left: 50%; width: 24%; height: 24%; transform: translate(-50%, -50%);
              border-radius: 50%; background: #fff; padding: 0.35mm; }
  .pn { font-size: 7.5pt; font-weight: 700; line-height: 1; letter-spacing: 0.02em; white-space: nowrap; }
  @media screen {
    html, body { width: auto; height: auto; }
    body { background: #e5e7eb; min-height: 100vh; display: flex; align-items: center; justify-content: center; }
    .label { background: #fff; outline: 1px dashed #9ca3af; }
  }
`

// `qrHtml` is an <img> or <svg> of the QR code.
export function printQrSticker({ qrHtml, propertyNumber }) {
  const sealUrl = `${window.location.origin}/logo-qr.png`
  openWindow({ width: 360, height: 360, waiting: 'Preparing the sticker…' }).write(`<!DOCTYPE html><html><head>
  <title>QR Sticker – ${escapeHtml(propertyNumber)}</title>
  <style>${STICKER_STYLES}</style></head><body>
  <div class="label">
    <div class="qr">${qrHtml}<img class="seal" src="${sealUrl}" alt="" /></div>
    <p class="pn">${escapeHtml(propertyNumber)}</p>
  </div>
  <script>window.onload = () => { window.print(); window.onafterprint = () => window.close() }<\/script>
  </body></html>`)
}

// Many stickers at once (bulk QR export). layout 'labels': one 30 × 30 mm sticker per page, for
// a label printer. layout 'a4': the same stickers in rows on A4 with light cut lines, for sticker
// paper or plain paper. `win` is a window opened right on the click (browsers block pop-ups
// opened after waiting for the server); stickers are { propertyNumber, qrSvg }.
const SHEET_STYLES = {
  labels: `
    @page { size: 30mm 30mm; margin: 0; }
    .label { page-break-after: always; break-after: page; }
    .label:last-child { page-break-after: auto; break-after: auto; }`,
  a4: `
    @page { size: A4; margin: 10mm; }
    .sheet { display: grid; grid-template-columns: repeat(6, 30mm); gap: 2mm; }
    .label { outline: 0.2mm dashed #bbb; break-inside: avoid; page-break-inside: avoid; }`,
}

export function openPrintWindow() {
  return openWindow({ width: 900, height: 700, waiting: 'Preparing QR codes…' })
}

export function printQrSheet(win, stickers, layout = 'a4') {
  const sealUrl = `${window.location.origin}/logo-qr.png`
  const labels = stickers.map((s) => `
    <div class="label">
      <div class="qr">${s.qrSvg}<img class="seal" src="${sealUrl}" alt="" /></div>
      <p class="pn">${escapeHtml(s.propertyNumber)}</p>
    </div>`).join('')
  win.write(`<!DOCTYPE html><html><head>
  <title>QR codes (${stickers.length})</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: Arial, Helvetica, sans-serif; color: #000; background: #fff;
           -webkit-print-color-adjust: exact; print-color-adjust: exact; }
    .label { width: 30mm; height: 30mm; padding: 1.5mm; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 0.6mm; overflow: hidden; background: #fff; }
    .qr { position: relative; flex: none; width: 22.5mm; height: 22.5mm; }
    .qr > svg { display: block; width: 100%; height: 100%; }
    .qr .seal { position: absolute; top: 50%; left: 50%; width: 24%; height: 24%; transform: translate(-50%, -50%);
                border-radius: 50%; background: #fff; padding: 0.35mm; }
    .pn { font-size: 7.5pt; font-weight: 700; line-height: 1; letter-spacing: 0.02em; white-space: nowrap; }
    ${SHEET_STYLES[layout] || SHEET_STYLES.a4}
    @media screen {
      body { background: #e5e7eb; padding: 16px; }
      .sheet { display: flex; flex-wrap: wrap; gap: 8px; }
      .label { outline: 1px dashed #9ca3af; }
    }
  </style></head><body>
  <div class="sheet">${labels}</div>
  <script>
    // wait for the seal image so it is on every sticker, then print
    const seal = new Image(); seal.src = ${JSON.stringify(sealUrl)};
    const go = () => { window.print() };
    seal.complete ? go() : (seal.onload = seal.onerror = go);
  <\/script>
  </body></html>`)
}
