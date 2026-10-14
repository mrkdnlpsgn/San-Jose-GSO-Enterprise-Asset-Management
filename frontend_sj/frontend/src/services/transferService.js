import api from './api';

// Transfer Asset page. An admin's transfer applies at once; a staff member's is a
// request (status PENDING_APPROVAL) until an admin approves or rejects it.
export const getTransfers    = (status)   => api.get('/transfers', { params: status ? { status } : {} });
export const submitTransfer  = (data)     => api.post('/transfers', data);
export const approveTransfer = (id)       => api.post(`/transfers/${id}/approve`);
export const rejectTransfer  = (id, note) => api.post(`/transfers/${id}/reject`, { note });
