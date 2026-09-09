import api from './api';

// Same reasoning as assetService.js's getAssets(): the Maintenance page expects
// the full list for client-side filtering/pagination, but the backend defaults
// to a 20-row page — request an effectively-unlimited page explicitly.
export const getMaintenance        = (search = '') => api.get('/maintenance', {
  params: { size: 100000, ...(search.trim() ? { search: search.trim() } : {}) },
});
export const getMaintenanceById    = (id)        => api.get(`/maintenance/${id}`);
export const getMaintenanceByAsset = (assetId)   => api.get(`/maintenance/asset/${assetId}`);
export const createMaintenance     = (data, idempotencyKey)      => api.post('/maintenance', data, idempotencyKey ? { headers: { 'Idempotency-Key': idempotencyKey } } : undefined);
export const updateMaintenance     = (id, data)  => api.put(`/maintenance/${id}`, data);
export const deleteMaintenance     = (id, body)  => api.delete(`/maintenance/${id}`, { data: body });

export const getMaintenancePhotos    = (id)       => api.get(`/maintenance/${id}/photos`);
export const uploadMaintenancePhoto  = (id, file) => {
  const formData = new FormData();
  formData.append('file', file);
  return api.post(`/maintenance/${id}/photos`, formData, { headers: { 'Content-Type': 'multipart/form-data' } });
};
export const deleteMaintenancePhoto  = (id, photoId) => api.delete(`/maintenance/${id}/photos/${photoId}`);
