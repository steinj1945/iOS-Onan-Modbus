import { Routes, Route, Navigate } from 'react-router-dom'
import Login from './pages/Login'
import Keys from './pages/Keys'
import Logs from './pages/Logs'
import Layout from './components/Layout'

function RequireAuth({ children }: { children: React.ReactNode }) {
  return localStorage.getItem('token') ? <>{children}</> : <Navigate to="/login" replace />
}

export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<Login />} />
      <Route path="/" element={<RequireAuth><Layout /></RequireAuth>}>
        <Route index element={<Navigate to="/keys" replace />} />
        <Route path="keys" element={<Keys />} />
        <Route path="logs" element={<Logs />} />
      </Route>
    </Routes>
  )
}
