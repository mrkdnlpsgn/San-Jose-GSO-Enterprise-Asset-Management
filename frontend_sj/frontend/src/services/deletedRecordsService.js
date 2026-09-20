import api from './api';

export const getDeletedAssets      = () => api.get('/deleted-records/assets');
export const getDeletedMaintenance = () => api.get('/deleted-records/maintenance');
export const getDeletedDisposal    = () => api.get('/deleted-records/disposal');

export const restoreDeletedAsset       = (id) => api.post(`/deleted-records/assets/${id}/restore`);
export const restoreDeletedMaintenance = (id) => api.post(`/deleted-records/maintenance/${id}/restore`);
export const restoreDeletedDisposal    = (id) => api.post(`/deleted-records/disposal/${id}/restore`);

// Step-up 2FA — emails a one-time code to the current user before a permanent delete.
export const requestDeleteOtp = () => api.post('/auth/delete-otp/request');

// Each permanently deletes both the underlying record and its Recycle Bin
// snapshot — irreversible, and requires the OTP from requestDeleteOtp().
export const permanentDeleteAsset       = (id, otp) => api.post(`/deleted-records/assets/${id}/permanent-delete`, { otp });
export const permanentDeleteMaintenance = (id, otp) => api.post(`/deleted-records/maintenance/${id}/permanent-delete`, { otp });
export const permanentDeleteDisposal    = (id, otp) => api.post(`/deleted-records/disposal/${id}/permanent-delete`, { otp });
