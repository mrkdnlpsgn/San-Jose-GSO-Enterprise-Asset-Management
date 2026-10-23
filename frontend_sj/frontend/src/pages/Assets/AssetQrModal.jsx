import { useEffect, useState } from 'react'
import { useDispatch, useSelector } from 'react-redux'
import Modal from '../../components/common/Modal'
import Button from '../../components/common/Button'
import ConfirmDialog from '../../components/common/ConfirmDialog'
import { useToast } from '../../context/ToastContext'
import { getAssetQrCode, reissueAssetQr } from '../../services/assetService'
import { updateAsset } from '../../store/slices/assetSlice'
import { printQrSticker } from '../../utils/printQrSticker'

function AssetQrModal({ asset, onClose }) {
  const dispatch = useDispatch()
  const { show } = useToast()
  const isAdmin  = useSelector((s) => s.auth.user?.role === 'ADMIN')
  const [imgUrl, setImgUrl] = useState(null)
  const [error, setError] = useState('')
  // Bumped after a reissue so the image is fetched again with the new signature.
  const [qrVersion, setQrVersion] = useState(0)
  const [confirmReissue, setConfirmReissue] = useState(false)
  const [reissuing, setReissuing] = useState(false)

  const handleReissue = async () => {
    setConfirmReissue(false)
    setReissuing(true)
    try {
      const { data } = await reissueAssetQr(asset.id)
      dispatch(updateAsset(data))
      setImgUrl(null)
      setQrVersion((v) => v + 1)
      show('New QR code issued. Print it and replace the old sticker. The old one no longer verifies.', 'success')
    } catch (err) {
      show(err.response?.data?.message || 'Failed to reissue the QR code.', 'error')
    } finally {
      setReissuing(false)
    }
  }

  useEffect(() => {
    let objectUrl
    let cancelled = false
    getAssetQrCode(asset.id)
      .then(({ data }) => {
        if (cancelled) return
        objectUrl = URL.createObjectURL(data)
        setImgUrl(objectUrl)
      })
      .catch(() => { if (!cancelled) setError('Failed to generate QR code.') })
    return () => {
      cancelled = true
      if (objectUrl) URL.revokeObjectURL(objectUrl)
    }
  }, [asset.id, qrVersion])

  return (
    <Modal title="Asset QR Code" subtitle={asset.propertyNumber} onClose={onClose} size="md">
      <div className="flex flex-col items-center gap-4 py-2">
        <div className="bg-white p-5 rounded-2xl shadow-lg h-[220px] w-[220px] flex items-center justify-center">
          {error ? (
            <p className="text-sm text-red-500 text-center px-2">{error}</p>
          ) : imgUrl ? (
            <div className="relative h-[200px] w-[200px]">
              <img src={imgUrl} alt={`QR code for ${asset.propertyNumber}`} width={200} height={200} />
              <img src="/logo-qr.png" alt="" className="absolute top-1/2 left-1/2 h-12 w-12 -translate-x-1/2 -translate-y-1/2 rounded-full bg-white p-0.5" />
            </div>
          ) : (
            <div className="animate-pulse h-[200px] w-[200px] rounded-lg bg-slate-100" />
          )}
        </div>

        <div className="space-y-1 text-center">
          <p className="text-base font-semibold text-slate-900 dark:text-white">{asset.description}</p>
          <p className="text-xs text-slate-500 dark:text-zinc-500">Scan with the mobile app to check this asset's status</p>
          {isAdmin && (
            <button
              type="button"
              onClick={() => setConfirmReissue(true)}
              disabled={reissuing}
              className="text-xs font-semibold text-red-600 dark:text-red-400 hover:text-red-700 dark:hover:text-red-300 disabled:opacity-60 transition-colors"
            >
              {reissuing ? 'Reissuing…' : 'Sticker lost or stolen? Reissue QR'}
            </button>
          )}
        </div>

        <div className="flex gap-2 w-full pt-1 border-t border-slate-100 dark:border-zinc-800">
          <Button variant="secondary" size="md" onClick={onClose} className="flex-1">Close</Button>
          <Button size="md" onClick={() => printQrSticker({ qrHtml: `<img src="${imgUrl}" alt="QR code" />`, propertyNumber: asset.propertyNumber })} disabled={!imgUrl} className="flex-1">
            <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 mr-1.5" viewBox="0 0 20 20" fill="currentColor">
              <path fillRule="evenodd" d="M5 4v3H4a2 2 0 00-2 2v3a2 2 0 002 2h1v2a2 2 0 002 2h6a2 2 0 002-2v-2h1a2 2 0 002-2V9a2 2 0 00-2-2h-1V4a2 2 0 00-2-2H7a2 2 0 00-2 2zm8 0H7v3h6V4zm0 8H7v4h6v-4z" clipRule="evenodd" />
            </svg>
            Print Label
          </Button>
        </div>
      </div>
      {confirmReissue && (
        <ConfirmDialog
          title="Reissue this QR code?"
          message={`Every sticker already printed for ${asset.propertyNumber} will fail verification when scanned. Print the new sticker and put it on the asset.`}
          confirmLabel="Reissue"
          onConfirm={handleReissue}
          onCancel={() => setConfirmReissue(false)}
        />
      )}
    </Modal>
  )
}

export default AssetQrModal
