import { useState } from 'react'
import { renderToStaticMarkup } from 'react-dom/server'
import { QRCodeSVG } from 'qrcode.react'
import Modal from '../../components/common/Modal'
import Button from '../../components/common/Button'
import { useToast } from '../../context/ToastContext'
import { getQrStickers } from '../../services/assetService'
import { openPrintWindow, printQrSheet } from '../../utils/printQrSticker'

const LAYOUTS = [
  { value: 'a4',     title: 'A4 sheet',      text: 'Six stickers across, with cut lines. For sticker paper or plain paper.' },
  { value: 'labels', title: 'Label printer', text: 'One 30 × 30 mm sticker per label.' },
]

// Bulk QR export for the assets ticked on the Assets list. The QR codes are the same signed
// codes as a single asset's sticker (level H, so the seal in the middle doesn't stop a scan).
// The print view opens in a new window; "Save as PDF" in the print dialog gives a file.
function QrExportModal({ ids, onClose, onDone }) {
  const { show } = useToast()
  const [layout, setLayout] = useState('a4')
  const [working, setWorking] = useState(false)

  const exportCodes = async () => {
    const win = openPrintWindow()
    setWorking(true)
    try {
      const { data } = await getQrStickers(ids)
      if (!data.length) {
        win.close()
        show('None of the chosen assets can be printed.', 'error')
        return
      }
      const stickers = data.map((s) => ({
        propertyNumber: s.propertyNumber,
        qrSvg: renderToStaticMarkup(<QRCodeSVG value={s.qrPayload} level="H" marginSize={2} bgColor="#ffffff" fgColor="#000000" />),
      }))
      printQrSheet(win, stickers, layout)
      if (data.length < ids.length) {
        show(`${ids.length - data.length} of the chosen assets were left out (deleted or not yours to view).`, 'info')
      }
      onDone()
    } catch (err) {
      win.close()
      show(err.response?.data?.message || 'Could not prepare the QR codes.', 'error')
    } finally {
      setWorking(false)
    }
  }

  return (
    <Modal title="Export QR codes" subtitle={`${ids.length.toLocaleString('en-PH')} asset${ids.length === 1 ? '' : 's'} chosen`} onClose={onClose} size="md">
      <fieldset className="space-y-2">
        <legend className="text-sm font-medium text-slate-700 dark:text-zinc-200 mb-2">Print on</legend>
        {LAYOUTS.map((l) => (
          <label key={l.value}
            className={`flex items-start gap-3 rounded-lg border px-3.5 py-3 cursor-pointer transition-colors ${
              layout === l.value ? 'border-brand-600 bg-brand-500/5' : 'border-slate-200 dark:border-zinc-700 hover:bg-slate-50 dark:hover:bg-zinc-800/50'}`}>
            <input type="radio" name="qr-layout" value={l.value} checked={layout === l.value} onChange={() => setLayout(l.value)}
              className="mt-0.5 h-4 w-4 accent-brand-600" />
            <span>
              <span className="block text-sm font-semibold text-slate-900 dark:text-white">{l.title}</span>
              <span className="block text-xs text-slate-600 dark:text-zinc-400 mt-0.5">{l.text}</span>
            </span>
          </label>
        ))}
      </fieldset>
      <p className="text-xs text-slate-600 dark:text-zinc-400 mt-3">
        The print view opens in a new window. To keep a file instead, choose "Save as PDF" as the printer.
      </p>
      <div className="flex gap-2 mt-4 pt-3 border-t border-slate-100 dark:border-zinc-800">
        <Button variant="secondary" size="md" onClick={onClose} className="flex-1">Cancel</Button>
        <Button size="md" onClick={exportCodes} disabled={working} className="flex-1">
          {working ? 'Preparing…' : 'Open print view'}
        </Button>
      </div>
    </Modal>
  )
}

export default QrExportModal
