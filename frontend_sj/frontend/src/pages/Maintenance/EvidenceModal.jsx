import EvidenceModal from '../../components/common/EvidenceModal'

// Maintenance record evidence — the shared evidence modal pointed at the record's photos.
function MaintenanceEvidenceModal({ record, onClose }) {
  return (
    <EvidenceModal
      path={`/maintenance/${record.id}/photos`}
      title="Inspection Evidence"
      subtitle={`${record.asset?.propertyNumber || ''} — ${record.asset?.description || ''}`}
      onClose={onClose}
    />
  )
}

export default MaintenanceEvidenceModal
