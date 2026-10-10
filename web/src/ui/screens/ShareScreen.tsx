import { useEffect, useRef } from 'react';
import { useNavigate, useSearchParams } from 'react-router';
import { extractUrl, titleFromShareText } from '../../data/urlUtils';
import { useSheets } from '../components/Sheet';
import { AddLinkSheet } from '../sheets/AddLinkSheet';

/**
 * Web Share Target: with Shareby installed from the browser on Android, it appears in
 * other apps' share sheet and lands here with ?title=&text=&url=.
 */
export function ShareScreen() {
  const [params] = useSearchParams();
  const navigate = useNavigate();
  const sheets = useSheets();
  const handled = useRef(false);

  useEffect(() => {
    if (handled.current) return;
    handled.current = true;
    const text = [params.get('title'), params.get('text'), params.get('url')].filter(Boolean).join(' ');
    const url = extractUrl(params.get('url')) ?? extractUrl(text);
    navigate('/', { replace: true });
    if (url) sheets.open(<AddLinkSheet fromShare initialUrl={url} initialTitle={titleFromShareText(text.replace(url, ''), url)} />);
  }, [params, navigate, sheets]);

  return null;
}
