import EvidenceModal from '../../components/common/EvidenceModal'

// Pre- and post-maintenance photos: the asset as found before the work, and the finished work.
const MAINTENANCE_PHOTO_STAGES = [
  { key: 'BEFORE', label: 'Pre-maintenance', hint: 'The asset as found, before any work: the damage or problem.' },
  { key: 'AFTER',  label: 'Post-maintenance', hint: 'The finished work: replaced parts, the repaired asset.' },
]

// Maintenance record evidence - the shared evidence modal pointed at the record's photos.
function MaintenanceEvidenceModal({ record, onClose }) {
  return (
    <EvidenceModal
      path={`/maintenance/${record.id}/photos`}
      title="Maintenance Photos"
      subtitle={`${record.asset?.propertyNumber || ''}: ${record.asset?.description || ''}`}
      onClose={onClose}
      stages={MAINTENANCE_PHOTO_STAGES}
    />
  )
}

export default MaintenanceEvidenceModal
