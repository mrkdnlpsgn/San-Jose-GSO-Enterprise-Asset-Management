import { useState, useEffect, useCallback } from 'react'
import { Link, useLocation } from 'react-router-dom'
import Button from './Button'
import ConfirmDialog from './ConfirmDialog'
import { useToast } from '../../context/ToastContext'
import api from '../../services/api'

// Property number format, and the one-time renumbering of existing assets to it. Shown on the
// Categories and Offices pages, where the codes it needs are set. `refreshKey` reloads the
// counts after a code is saved.
export default function PropertyNumberPanel({ refreshKey }) {
  const toast = useToast()
  const here = useLocation().pathname
  const [status, setStatus] = useState(null)
  const [confirming, setConfirming] = useState(false)
  const [working, setWorking] = useState(false)

  const load = useCallback(() => {
    api.get('/property-numbers/status').then(({ data }) => setStatus(data)).catch(() => setStatus(null))
  }, [])
  useEffect(() => { load() }, [load, refreshKey])

  const renumber = async () => {
    setConfirming(false)
    setWorking(true)
    try {
      const { data } = await api.post('/property-numbers/renumber')
      setStatus(data)
      toast.show(`${data.renumbered.toLocaleString('en-PH')} asset${data.renumbered === 1 ? '' : 's'} renumbered. Reprint their QR stickers.`, 'success')
    } catch (err) {
      toast.show(err.response?.data?.message || 'Could not renumber the assets.', 'error')
    } finally {
      setWorking(false)
    }
  }

  const missing = (names, page, nouns) => names?.length > 0 && (
    <p className="text-xs text-amber-800 dark:text-amber-300">
      {names.length} {nouns[names.length === 1 ? 0 : 1]} without a code: {names.slice(0, 6).join(', ')}{names.length > 6 ? `, and ${names.length - 6} more` : ''}.
      {here !== page && <>{' '}<Link to={page} className="font-medium underline">Set them on the {page === '/categories' ? 'Categories' : 'Offices'} page</Link>.</>}
    </p>
  )

  return (
    <section aria-labelledby="pn-heading" className="mb-4 rounded-xl border border-slate-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 px-5 py-4">
      <div className="flex flex-col sm:flex-row sm:items-start gap-3">
        <div className="flex-1 min-w-0 space-y-1.5">
          <h2 id="pn-heading" className="text-sm font-semibold text-slate-800 dark:text-zinc-200">Property number format</h2>
          <p className="text-sm text-slate-700 dark:text-zinc-300">
            <span className="font-mono">YEAR-CATEGORY-SERIAL-OFFICE</span>, e.g. <span className="font-mono">2024-05030-012-1011</span>.
            {' '}The year comes from the acquisition date, the serial counts up per category, and the office code changes when an asset is transferred.
          </p>
          {status && (
            <>
              {missing(status.categoriesMissingCode, '/categories', ['category', 'categories'])}
              {missing(status.officesMissingCode, '/offices', ['office', 'offices'])}
              <p className="text-xs text-slate-600 dark:text-zinc-400">
                {status.toRenumber.toLocaleString('en-PH')} asset{status.toRenumber === 1 ? '' : 's'} can be renumbered now
                {status.alreadyCurrent > 0 && `, ${status.alreadyCurrent.toLocaleString('en-PH')} already use the format`}
                {status.blocked > 0 && `, ${status.blocked.toLocaleString('en-PH')} wait for a missing code`}.
              </p>
            </>
          )}
        </div>
        <Button variant="secondary" size="md" className="flex-shrink-0" disabled={!status?.toRenumber || working} onClick={() => setConfirming(true)}>
          {working ? 'Renumbering…' : 'Renumber assets'}
        </Button>
      </div>
      {confirming && (
        <ConfirmDialog
          title="Renumber assets?"
          message={`${status.toRenumber.toLocaleString('en-PH')} asset${status.toRenumber === 1 ? '' : 's'} will get a new property number in the new format. Their printed QR stickers will stop working and must be reprinted (Assets page, QR codes). This can't be undone.`}
          confirmLabel="Renumber"
          onConfirm={renumber}
          onCancel={() => setConfirming(false)}
        />
      )}
    </section>
  )
}
