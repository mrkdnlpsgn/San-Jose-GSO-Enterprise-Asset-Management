import api from './api';

// Articles: the kinds of item under each category (ICT Equipment > Laptop).
export const getArticles   = (categoryId) => api.get('/articles', categoryId ? { params: { categoryId } } : undefined);
export const createArticle = (data)       => api.post('/articles', data);
export const updateArticle = (id, data)   => api.put(`/articles/${id}`, data);
export const deleteArticle = (id)         => api.delete(`/articles/${id}`);
