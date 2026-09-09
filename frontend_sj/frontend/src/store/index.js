import { configureStore } from '@reduxjs/toolkit'
import authReducer     from './slices/authSlice'
import assetReducer    from './slices/assetSlice'
import presenceReducer from './slices/presenceSlice'

export const store = configureStore({
  reducer: {
    auth:     authReducer,
    assets:   assetReducer,
    presence: presenceReducer,
  },
})
