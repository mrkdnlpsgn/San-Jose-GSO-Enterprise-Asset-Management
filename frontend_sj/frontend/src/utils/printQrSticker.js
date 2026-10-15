import { escapeHtml } from './helpers'

// Prints one asset QR sticker at the common 50 × 30 mm asset-tag size. `@page` sets the
// paper to the sticker itself, so a label printer puts one tag per label. Text is pure
// black for thermal printers, and the QR keeps a white margin of a few mm so it still
// scans when the sticker is cut slightly off.
const STICKER_STYLES = `
  @page { size: 50mm 30mm; margin: 0; }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  html, body { width: 50mm; height: 30mm; }
  body { font-family: Arial, Helvetica, sans-serif; color: #000; background: #fff;
         -webkit-print-color-adjust: exact; print-color-adjust: exact; }
  .label { width: 50mm; height: 30mm; padding: 2.5mm; display: flex; align-items: center; gap: 2mm; overflow: hidden; }
  .qr { flex: none; width: 23mm; height: 23mm; }
  .qr img, .qr svg { display: block; width: 100%; height: 100%; }
  .text { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 1mm; }
  .pn { font-size: 8pt; font-weight: 700; line-height: 1.1; overflow-wrap: anywhere; }
  .desc { font-size: 6pt; line-height: 1.15; overflow: hidden; display: -webkit-box; -webkit-line-clamp: 3; -webkit-box-orient: vertical; overflow-wrap: anywhere; }
  .org { font-size: 5pt; line-height: 1.15; border-top: 0.2mm solid #000; padding-top: 0.8mm; }
  @media screen {
    html, body { width: auto; height: auto; }
    body { background: #e5e7eb; min-height: 100vh; display: flex; align-items: center; justify-content: center; }
    .label { background: #fff; outline: 1px dashed #9ca3af; }
  }
`

// `qrHtml` is an <img> or <svg> of the QR code.
export function printQrSticker({ qrHtml, propertyNumber, description }) {
  const win = window.open('', '_blank', 'width=480,height=360')
  if (!win) return
  win.document.write(`<!DOCTYPE html><html><head>
  <title>QR Sticker – ${escapeHtml(propertyNumber)}</title>
  <style>${STICKER_STYLES}</style></head><body>
  <div class="label">
    <div class="qr">${qrHtml}</div>
    <div class="text">
      <p class="pn">${escapeHtml(propertyNumber)}</p>
      <p class="desc">${escapeHtml(description) || '—'}</p>
      <p class="org">San Jose Municipal Hall</p>
    </div>
  </div>
  <script>window.onload = () => { window.print(); window.onafterprint = () => window.close() }<\/script>
  </body></html>`)
  win.document.close()
}
