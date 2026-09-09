import { useState, useEffect, useRef } from 'react'
import Modal from '../../components/common/Modal'
import ConfirmDialog from '../../components/common/ConfirmDialog'
import { useToast } from '../../context/ToastContext'
import { getMaintenancePhotos, uploadMaintenancePhoto, deleteMaintenancePhoto } from '../../services/maintenanceService'
import { resolveUploadUrl } from '../../services/api'

const MAX_SIZE = 10 * 1024 * 1024
const ACCEPTED = ['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']

function formatSize(bytes) {
  if (!bytes) return ''
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
}

function EvidenceModal({ record, onClose }) {
  const toast = useToast()
  const fileInputRef = useRef(null)

  const [photos, setPhotos]   = useState([])
  const [loading, setLoading] = useState(true)
  const [uploading, setUploading] = useState(false)
  const [deleting, setDeleting]   = useState(null) // photo pending delete confirmation
  const [preview, setPreview]     = useState(null) // photo being viewed full-size

  useEffect(() => {
    let cancelled = false
    setLoading(true)
    getMaintenancePhotos(record.id)
      .then(({ data }) => { if (!cancelled) setPhotos(data) })
      .catch(() => { if (!cancelled) toast.show('Failed to load evidence photos.', 'error') })
      .finally(() => { if (!cancelled) setLoading(false) })
    return () => { cancelled = true }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [record.id])

  const handleFiles = async (fileList) => {
    const files = Array.from(fileList || [])
    if (files.length === 0) return

    for (const file of files) {
      if (!ACCEPTED.includes(file.type)) {
        toast.show(`${file.name}: only JPEG, PNG, WEBP, or HEIC images are allowed.`, 'error')
        continue
      }
      if (file.size > MAX_SIZE) {
        toast.show(`${file.name}: exceeds the 10 MB limit.`, 'error')
        continue
      }
      setUploading(true)
      try {
        const { data } = await uploadMaintenancePhoto(record.id, file)
        setPhotos((prev) => [data, ...prev])
      } catch (err) {
        toast.show(err.response?.data?.message || `Failed to upload ${file.name}.`, 'error')
      } finally {
        setUploading(false)
      }
    }
  }

  const handleDelete = async () => {
    const photo = deleting
    setDeleting(null)
    try {
      await deleteMaintenancePhoto(record.id, photo.id)
      setPhotos((prev) => prev.filter((p) => p.id !== photo.id))
      toast.show('Photo removed.', 'warning')
    } catch (err) {
      toast.show(err.response?.data?.message || 'Failed to delete photo.', 'error')
    }
  }

  return (
    <Modal
      title="Inspection Evidence"
      subtitle={`${record.asset?.propertyNumber || ''} — ${record.asset?.description || ''}`}
      onClose={onClose}
    >
      <div className="space-y-4">
        <div>
          <input
            ref={fileInputRef}
            type="file"
            accept={ACCEPTED.join(',')}
            multiple
            className="hidden"
            onChange={(e) => { handleFiles(e.target.files); e.target.value = '' }}
          />
          <button
            type="button"
            disabled={uploading}
            onClick={() => fileInputRef.current?.click()}
            className="w-full flex flex-col items-center justify-center gap-1.5 rounded-lg border-2 border-dashed border-slate-200 dark:border-zinc-700 hover:border-brand-500/50 hover:bg-slate-50 dark:hover:bg-zinc-800/40 transition-all duration-150 py-6 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            <svg xmlns="http://www.w3.org/2000/svg" className={`h-6 w-6 text-slate-400 dark:text-zinc-500 ${uploading ? 'animate-pulse' : ''}`} fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M3 16.5v2.25A2.25 2.25 0 005.25 21h13.5A2.25 2.25 0 0021 18.75V16.5M16.5 8.25L12 3.75m0 0L7.5 8.25M12 3.75v12.75" />
            </svg>
            <span className="text-xs font-medium text-slate-500 dark:text-zinc-400">
              {uploading ? 'Uploading…' : 'Click to upload evidence photos'}
            </span>
            <span className="text-2xs text-slate-400 dark:text-zinc-600">JPEG, PNG, WEBP, or HEIC — up to 10 MB each</span>
          </button>
        </div>

        {loading ? (
          <div className="grid grid-cols-3 gap-3">
            {Array.from({ length: 3 }).map((_, i) => (
              <div key={i} className="animate-pulse aspect-square rounded-lg bg-slate-200 dark:bg-zinc-800" />
            ))}
          </div>
        ) : photos.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-10 gap-2">
            <svg xmlns="http://www.w3.org/2000/svg" className="h-9 w-9 text-slate-200 dark:text-zinc-800" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1} d="M3 16.5l5.379-5.379a2.25 2.25 0 013.182 0l5.94 5.94M14.25 12l1.379-1.379a2.25 2.25 0 013.182 0L21 12.75M3 6.75A2.25 2.25 0 015.25 4.5h13.5A2.25 2.25 0 0121 6.75v10.5A2.25 2.25 0 0118.75 19.5H5.25A2.25 2.25 0 013 17.25V6.75zM9.75 9a1.5 1.5 0 11-3 0 1.5 1.5 0 013 0z" />
            </svg>
            <p className="text-sm text-slate-400 dark:text-zinc-600">No evidence photos yet.</p>
          </div>
        ) : (
          <div className="grid grid-cols-3 gap-3">
            {photos.map((photo) => (
              <div key={photo.id} className="group relative aspect-square rounded-lg overflow-hidden bg-slate-100 dark:bg-zinc-800 border border-slate-200 dark:border-zinc-700">
                <img
                  src={resolveUploadUrl(photo.url)}
                  alt={photo.originalFilename || 'Evidence photo'}
                  className="w-full h-full object-cover cursor-pointer transition-transform duration-150 group-hover:scale-105"
                  onClick={() => setPreview(photo)}
                />
                <button
                  type="button"
                  title="Delete photo"
                  onClick={() => setDeleting(photo)}
                  className="absolute top-1.5 right-1.5 p-1 rounded-md bg-black/50 text-white opacity-0 group-hover:opacity-100 hover:bg-red-600 transition-all duration-150"
                >
                  <svg xmlns="http://www.w3.org/2000/svg" className="h-3.5 w-3.5" viewBox="0 0 20 20" fill="currentColor">
                    <path fillRule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clipRule="evenodd" />
                  </svg>
                </button>
              </div>
            ))}
          </div>
        )}
      </div>

      {preview && (
        <div
          className="fixed inset-0 z-[70] flex items-center justify-center p-6 bg-black/80 animate-fade-slide"
          onClick={() => setPreview(null)}
        >
          <img src={resolveUploadUrl(preview.url)} alt={preview.originalFilename || 'Evidence photo'} className="max-h-full max-w-full rounded-lg shadow-2xl" />
          <div className="absolute bottom-6 left-1/2 -translate-x-1/2 text-center text-white/70 text-xs">
            {preview.originalFilename} {preview.fileSize ? `· ${formatSize(preview.fileSize)}` : ''}
          </div>
        </div>
      )}

      {deleting && (
        <ConfirmDialog
          title="Delete this photo?"
          message="This evidence photo will be permanently removed."
          confirmLabel="Delete"
          onConfirm={handleDelete}
          onCancel={() => setDeleting(null)}
        />
      )}
    </Modal>
  )
}

export default EvidenceModal
