import unittest
from pipeline.m3u import validate_m3u, parse_m3u, content_hash

class M3UTests(unittest.TestCase):
    def test_metadata_capture(self):
        text = '#EXTM3U\n#EXTINF:-1 tvg-id="A.us@SD" tvg-name="Alpha" tvg-logo="https://x/a.png" group-title="News",Alpha (1080p)\nhttps://x/a.m3u8\n'
        v = validate_m3u(text)
        self.assertTrue(v.ok)
        item = v.items[0]
        self.assertEqual(item.tvg_id, "A.us@SD")
        self.assertEqual(item.tvg_name, "Alpha")
        self.assertEqual(item.logo_url, "https://x/a.png")
        self.assertEqual(item.group, "News")

    def test_empty_and_html(self):
        self.assertFalse(validate_m3u("").ok)
        self.assertEqual(validate_m3u("<html>oops</html>").reason, "html")

    def test_truncated(self):
        v = validate_m3u("#EXTM3U\n#EXTINF:-1,Only")
        self.assertFalse(v.ok)
        self.assertEqual(v.reason, "truncated")

    def test_protocols_are_not_filtered(self):
        v = validate_m3u("#EXTM3U\n#EXTINF:-1 tvg-id=\"A\",A\nrtsp://example.test/a\n")
        self.assertTrue(v.ok)
        self.assertEqual(v.items[0].url, "rtsp://example.test/a")

    def test_hash_changes_with_url(self):
        a = '#EXTM3U\n#EXTINF:-1,A\nhttps://x/a.m3u8\n'
        b = '#EXTM3U\n#EXTINF:-1,A\nhttps://x/b.m3u8\n'
        self.assertNotEqual(content_hash(a), content_hash(b))

    def test_duplicate_urls(self):
        text = '#EXTM3U\n#EXTINF:-1,A\nhttps://x/a\n#EXTINF:-1,B\nhttps://x/a\n'
        v = validate_m3u(text)
        self.assertTrue(v.ok)
        self.assertEqual(len(v.items), 2)

if __name__ == "__main__":
    unittest.main()
