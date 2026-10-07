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
// Own profile picture (see ProfilePictureController) — `file` is a Blob/File image.
export const uploadAvatar    = (file)      => {
  const formData = new FormData();
  formData.append('file', file, 'avatar.jpg');
  return api.post('/users/me/avatar', formData, { headers: { 'Content-Type': 'multipart/form-data' } });
};
export const removeAvatar    = ()          => api.delete('/users/me/avatar');
// My Account page: own email, office, member-since, 2-step status and latest actions.
export const getMyOverview   = ()          => api.get('/users/me/overview');
// Own 2-step verification. Turning it off needs the current password.
export const setMyTwoFactor  = (enabled, currentPassword) => api.put('/users/me/two-factor', { enabled, currentPassword });
// Forget every computer remembered for 2-step — also signs this account out everywhere.
export const forgetMyDevices = ()          => api.post('/users/me/forget-devices');
