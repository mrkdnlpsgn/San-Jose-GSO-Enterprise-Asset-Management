import api from './api';

// Transfer Asset page. An admin's transfer applies at once; a staff member's is a
// request (status PENDING_APPROVAL) until an admin approves or rejects it.
export const getTransfers    = (status)   => api.get('/transfers', { params: status ? { status } : {} });
export const submitTransfer  = (data)     => api.post('/transfers', data);
export const approveTransfer = (id, newParNumber) => api.post(`/transfers/${id}/approve`, newParNumber ? { newParNumber } : {});
export const rejectTransfer  = (id, note) => api.post(`/transfers/${id}/reject`, { note });

// Property Return Slips and PARs made when an asset changed end user.
export const getReturnPapers = (assetId)  => api.get(`/assets/${assetId}/return-papers`);
