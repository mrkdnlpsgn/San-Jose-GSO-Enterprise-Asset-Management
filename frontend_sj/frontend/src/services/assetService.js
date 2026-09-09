import api from './api';

// Callers across the app (Dashboard, Reports, Maintenance, Disposal, etc.) expect
// the full asset list for client-side filtering/pagination, but the backend
// defaults to a 20-row page — request an effectively-unlimited page explicitly.
export const getAssets       = (search = '') => api.get('/assets', {
  params: { size: 100000, ...(search.trim() ? { search: search.trim() } : {}) },
});
export const getAssetById    = (id)        => api.get(`/assets/${id}`);
export const getAssetQrCode  = (id, size = 400) => api.get(`/assets/${id}/qr`, { params: { size }, responseType: 'blob' });
export const createAsset     = (data, idempotencyKey)      => api.post('/assets', data, idempotencyKey ? { headers: { 'Idempotency-Key': idempotencyKey } } : undefined);
export const updateAsset     = (id, data)  => api.put(`/assets/${id}`, data);
export const deleteAsset     = (id, body)  => api.delete(`/assets/${id}`, { data: body });
export const bulkImportAssets = (rows)     => api.post('/assets/bulk-import', rows);
