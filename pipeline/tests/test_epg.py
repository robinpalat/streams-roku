import tempfile
import unittest
from pathlib import Path

from pipeline.xmltv import parse_xmltv_time, parse_xmltv_files, channel_has_programs

NOW = 1795240800

class EpgTests(unittest.TestCase):
    def test_time_with_offset(self):
        self.assertEqual(parse_xmltv_time("20261121060000 +0000"), NOW)
        self.assertEqual(parse_xmltv_time("20261121070000 +0100"), NOW)

    def test_no_stop_counts_as_program(self):
        epg = parse_xmltv_files(["pipeline/fixtures/guide.xml"], NOW)
        ch = epg["channels"]["C.us@SD"]
        self.assertEqual(ch["programCount"], 1)
        self.assertEqual(ch["unknownDurationCount"], 1)
        self.assertFalse(ch["endKnown"])
        self.assertTrue(channel_has_programs(epg, "C.us@SD"))

    def test_channel_without_programs(self):
        epg = parse_xmltv_files(["pipeline/fixtures/guide.xml"], NOW)
        self.assertIn("B.us@SD", epg["channels"])
        self.assertFalse(channel_has_programs(epg, "B.us@SD"))

    def test_window_is_24_plus_6(self):
        epg = parse_xmltv_files(["pipeline/fixtures/guide.xml"], NOW)
        self.assertEqual(epg["windowStart"], NOW - 21600)
        self.assertEqual(epg["windowEnd"], NOW + 86400)
        starts = [p["s"] for p in epg["channels"]["A.us@SD"]["programs"]]
        self.assertTrue(all(s <= epg["windowEnd"] for s in starts))

    def test_duplicate_channel_uses_source_with_most_programs(self):
        one = """<?xml version="1.0"?><tv><channel id="A"><display-name>A</display-name></channel>
        <programme start="20261121050000 +0000" stop="20261121060000 +0000" channel="A"><title>One</title></programme></tv>"""
        two = """<?xml version="1.0"?><tv><channel id="A"><display-name>A</display-name></channel>
        <programme start="20261121050000 +0000" stop="20261121060000 +0000" channel="A"><title>One</title></programme>
        <programme start="20261121060000 +0000" stop="20261121070000 +0000" channel="A"><title>Two</title></programme></tv>"""
        with tempfile.TemporaryDirectory() as tmp:
            p1 = Path(tmp) / "one.xml"; p1.write_text(one)
            p2 = Path(tmp) / "two.xml"; p2.write_text(two)
            epg = parse_xmltv_files([p1, p2], NOW)
        self.assertEqual(epg["channels"]["A"]["programCount"], 2)

    def test_end_known(self):
        epg = parse_xmltv_files(["pipeline/fixtures/guide.xml"], NOW)
        self.assertTrue(epg["channels"]["A.us@SD"]["endKnown"])
        self.assertFalse(epg["channels"]["F.us@SD"]["endKnown"])

if __name__ == "__main__":
    unittest.main()
