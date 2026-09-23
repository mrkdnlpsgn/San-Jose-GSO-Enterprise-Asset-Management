import api from './api';

// Personnel = the accounts (created on the Accounts page); only editable here, for office etc.

export const getPersonnel    = (search = '') => search.trim()
  ? api.get('/personnel', { params: { search: search.trim() } })
  : api.get('/personnel');
export const updatePersonnel = (id, data)  => api.put(`/personnel/${id}`, data);
