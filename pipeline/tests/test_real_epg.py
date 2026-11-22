import json
import tempfile
import unittest
from pathlib import Path

from pipeline.build import ROOT, build_source
from pipeline.xmltv import parse_xmltv_files

NOW = 1795300000
REAL_DIR = ROOT / "pipeline" / "real"
GUIDES = [REAL_DIR / name for name in [
    "guide-mi.xml", "guide-gatotv.xml", "guide-imjh.xml",
    "guide-teleboy.xml", "guide-extra.xml",
]]
HAVE_REAL = all(path.exists() for path in GUIDES) and (REAL_DIR / "streams.m3u").exists()

@unittest.skipUnless(HAVE_REAL, "local real snapshots are not committed")
class RealEpgTests(unittest.TestCase):
    def test_merged_real_guide(self):
        epg = parse_xmltv_files(GUIDES, NOW)
        channels = epg["channels"]
        for cid in ["Mega.cl@SD", "13C.cl@SD", "24Horas.es@SD", "Historia.es@SD",
                    "Space.ar@Panregional", "Eurochannel.uk@SD", "StingrayClassica.ca@SD"]:
            self.assertIn(cid, channels)
            self.assertGreater(len(channels[cid]["programs"]), 0, cid)
        self.assertEqual(len(channels["CinePride.us@SD"]["programs"]), 0)
        self.assertGreater(len(channels["Space.ar@Panregional"]["programs"]), 0)

    def test_real_build_metrics(self):
        source = json.loads((ROOT / "pipeline" / "config" / "sources.json").read_text())["sources"]
        real = next(s for s in source if s["id"] == "real")
        with tempfile.TemporaryDirectory() as tmp:
            result = build_source(real, ROOT / "pipeline" / "config", Path(tmp), NOW, 400000)
            base = Path(tmp) / "real"
            coverage = json.loads((base / "coverage.json").read_text())
            manifest = json.loads((base / "latest.json").read_text())
            epg = json.loads((base / "epg.json").read_text())
            existing = {name: (base / name).exists() for name in
                        ["catalog.json", "epg.json", "coverage.json", "latest.json"]}
        self.assertEqual(result["channels"], 51)
        self.assertEqual(coverage["totals"]["mapped"], 40)
        self.assertEqual(coverage["totals"]["withPrograms"], 17)
        self.assertEqual(coverage["totals"]["notMapped"], 11)
        self.assertAlmostEqual(coverage["coverage"]["effective"], 17 / 51)
        self.assertEqual(len(epg["channels"]), 18)
        self.assertEqual(epg["channels"]["CinePride.us@SD"]["programCount"], 0)
        self.assertGreater(epg["channels"]["Eurochannel.uk@SD"]["programCount"], 0)
        self.assertIn("sourceErrors", coverage)
        self.assertEqual(manifest["schema"], 1)
        self.assertEqual(manifest["epg"]["file"], "epg.json")
        for name, exists in existing.items():
            self.assertTrue(exists, name)

if __name__ == "__main__":
    unittest.main()
