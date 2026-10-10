import { useLocation, useNavigate } from 'react-router';

/** Opening a folder remembers where you came from, so Back returns to that list. */
export function useOpenFolder() {
  const navigate = useNavigate();
  const location = useLocation();
  return (id: string) => navigate(`/folders/${id}`, { state: { from: location.pathname } });
}
