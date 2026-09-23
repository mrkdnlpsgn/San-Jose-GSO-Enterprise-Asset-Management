import api from './api';

export const getUsers        = (search = '') => search.trim()
  ? api.get('/users', { params: { search: search.trim() } })
  : api.get('/users');
export const createUser      = (data, idempotencyKey)      => api.post('/users', data, idempotencyKey ? { headers: { 'Idempotency-Key': idempotencyKey } } : undefined);
export const updateUser      = (id, data)  => api.put(`/users/${id}`, data);
// Accounts are deactivated, never deleted — assets can be handed to another account first.
export const deactivateUser  = (id, body)  => api.post(`/users/${id}/deactivate`, body || {});
export const changePassword  = (data)      => api.put('/users/me/password', data);
export const resetPassword   = (id, data)  => api.post(`/users/${id}/reset-password`, data);
