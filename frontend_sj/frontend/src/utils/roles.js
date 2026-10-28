// Account roles. ADMIN_STAFF ("Admin-Staff") works like STAFF - its changes go to an admin as
// requests and it can't approve or reject - but it sees the entire inventory and every staff request.
export const ROLE_OPTIONS = [
  { value: 'ADMIN', label: 'Administrator' },
  { value: 'ADMIN_STAFF', label: 'Admin-Staff' },
  { value: 'STAFF', label: 'GSO Staff' },
]

export const roleLabel = (role) => ROLE_OPTIONS.find((r) => r.value === role)?.label ?? 'GSO Staff'

// Sees every office's assets and every staff request (not only its own).
export const seesAllAssets = (role) => role === 'ADMIN' || role === 'ADMIN_STAFF'
