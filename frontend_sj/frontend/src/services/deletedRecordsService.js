import api from './api';

export const getDeletedAssets      = () => api.get('/deleted-records/assets');
export const getDeletedMaintenance = () => api.get('/deleted-records/maintenance');
export const getDeletedDisposal    = () => api.get('/deleted-records/disposal');

export const restoreDeletedAsset       = (id) => api.post(`/deleted-records/assets/${id}/restore`);
export const restoreDeletedMaintenance = (id) => api.post(`/deleted-records/maintenance/${id}/restore`);
export const restoreDeletedDisposal    = (id) => api.post(`/deleted-records/disposal/${id}/restore`);
