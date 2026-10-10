import { describe, expect, it } from 'vitest';
import { detectSource, extractUrl, titleFromShareText, youtubeThumbnail } from '../src/data/urlUtils';

describe('url helpers', () => {
  it('extracts the link from share text and trims punctuation', () => {
    expect(extractUrl('Check this! https://www.instagram.com/reel/Cx12ab/?igsh=xyz.')).toBe('https://www.instagram.com/reel/Cx12ab/?igsh=xyz');
    expect(extractUrl('no link')).toBeNull();
  });
  it('detects the source app', () => {
    expect(detectSource('https://vt.tiktok.com/ZS1/')).toBe('tiktok');
    expect(detectSource('https://youtu.be/dQw4w9WgXcQ')).toBe('youtube');
    expect(detectSource('https://example.com')).toBe('web');
  });
  it('derives YouTube thumbnails', () => {
    const t = 'https://img.youtube.com/vi/dQw4w9WgXcQ/hqdefault.jpg';
    expect(youtubeThumbnail('https://www.youtube.com/watch?v=dQw4w9WgXcQ')).toBe(t);
    expect(youtubeThumbnail('https://youtube.com/shorts/dQw4w9WgXcQ')).toBe(t);
    expect(youtubeThumbnail('https://instagram.com/p/x')).toBeNull();
  });
  it('uses the caption as the title', () => {
    const url = 'https://www.tiktok.com/@a/video/1';
    expect(titleFromShareText(`Resep sambal matah ${url}`, url)).toBe('Resep sambal matah');
    expect(titleFromShareText(url, url)).toBe('Saved from tiktok.com');
  });
});
