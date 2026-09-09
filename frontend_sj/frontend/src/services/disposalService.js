import api from './api';

// Same reasoning as assetService.js's getAssets(): the Disposal page expects
// the full list for client-side filtering/pagination, but the backend defaults
// to a 20-row page — request an effectively-unlimited page explicitly.
export const getDisposal        = (search = '') => api.get('/disposal', {
  params: { size: 100000, ...(search.trim() ? { search: search.trim() } : {}) },
});
export const getDisposalById    = (id)        => api.get(`/disposal/${id}`);
export const getDisposalByAsset = (assetId)   => api.get(`/disposal/asset/${assetId}`);
export const createDisposal     = (data, idempotencyKey)      => api.post('/disposal', data, idempotencyKey ? { headers: { 'Idempotency-Key': idempotencyKey } } : undefined);
export const updateDisposal     = (id, data)  => api.put(`/disposal/${id}`, data);
export const deleteDisposal     = (id, body)  => api.delete(`/disposal/${id}`, { data: body });
