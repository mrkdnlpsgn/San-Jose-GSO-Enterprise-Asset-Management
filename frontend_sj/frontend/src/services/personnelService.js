import api from './api';

// Personnel = the accounts (created on the Accounts page); only editable here, for office etc.

export const getPersonnel    = (search = '') => search.trim()
  ? api.get('/personnel', { params: { search: search.trim() } })
  : api.get('/personnel');
export const updatePersonnel = (id, data)  => api.put(`/personnel/${id}`, data);

// A person can be assigned to several offices: `offices` (primary first). Older responses only
// carry `office`, the primary one.
export const personOffices = (p) => (p?.offices?.length ? p.offices : p?.office ? [p.office] : [])
export const inOffice = (p, officeId) => !!officeId && personOffices(p).some((o) => String(o.id) === String(officeId))
