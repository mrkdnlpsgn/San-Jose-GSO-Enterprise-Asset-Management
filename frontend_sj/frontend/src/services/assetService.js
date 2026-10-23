import api from './api';

// Callers across the app (Dashboard, Reports, Maintenance, Disposal, etc.) expect
// the full asset list for client-side filtering/pagination, but the backend
// defaults to a 20-row page - request an effectively-unlimited page explicitly.
// summary: only the fields lists need (about a third of the download). Anything that shows or
// edits one asset in full must load it with getAssetById - editing a summary would drop fields.
export const getAssets       = (search = '', { summary = false } = {}) => api.get('/assets', {
  params: { size: 100000, ...(search.trim() ? { search: search.trim() } : {}), ...(summary ? { view: 'summary' } : {}) },
});
export const getAssetById    = (id)        => api.get(`/assets/${id}`);
export const getAssetQrCode  = (id, size = 400) => api.get(`/assets/${id}/qr`, { params: { size }, responseType: 'blob' });
// Checks a scanned sticker's signature → { status: VERIFIED | UNSIGNED | INVALID | NOT_FOUND, assetId }.
export const verifyAssetQr   = (code)      => api.get('/assets/verify-qr', { params: { code } });
// Admin: retire the asset's current sticker (lost/stolen) - returns the asset with its new qrPayload.
export const reissueAssetQr  = (id)        => api.post(`/assets/${id}/qr/reissue`);
export const createAsset     = (data, idempotencyKey)      => api.post('/assets', data, idempotencyKey ? { headers: { 'Idempotency-Key': idempotencyKey } } : undefined);
export const updateAsset     = (id, data)  => api.put(`/assets/${id}`, data);
export const updateAssetStatus = (id, condition, lifecycleStatus) =>
  api.put(`/assets/${id}/status`, { condition, lifecycleStatus });
export const deleteAsset     = (id, body)  => api.delete(`/assets/${id}`, { data: body });
export const bulkImportAssets = (rows)     => api.post('/assets/bulk-import', rows);

// Reads a photo of an asset tag/sticker via server-side OCR - returns
// { description, serialNumber } to pre-fill the Add Asset form for review.
export const scanAssetLabel = (file) => {
  const formData = new FormData();
  formData.append('file', file);
  return api.post('/assets/scan-label', formData, { headers: { 'Content-Type': 'multipart/form-data' } });
};

// Bulk QR export: [{ id, propertyNumber, description, qrPayload }] for the chosen assets, in order.
export const getQrStickers   = (ids)       => api.post('/assets/qr-stickers', { ids });
