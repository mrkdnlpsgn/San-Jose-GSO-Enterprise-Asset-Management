import api from './api';

export const getPersonnel    = (search = '') => search.trim()
  ? api.get('/personnel', { params: { search: search.trim() } })
  : api.get('/personnel');
export const createPersonnel = (data, idempotencyKey)      => api.post('/personnel', data, idempotencyKey ? { headers: { 'Idempotency-Key': idempotencyKey } } : undefined);
export const updatePersonnel = (id, data)  => api.put(`/personnel/${id}`, data);
export const deletePersonnel = (id)        => api.delete(`/personnel/${id}`);
