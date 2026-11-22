import json
import tempfile
import unittest
from pathlib import Path

from pipeline.build import ROOT, build_source
from pipeline.validate import validate

NOW = 1795240800

SOURCE = {
    "id": "fixture",
    "name": "Fixture",
    "m3u": "../fixtures/streams.m3u",
    "epg": ["../fixtures/guide.xml"],
    "data": {
        "channels": "../fixtures/api/channels.json",
        "feeds": "../fixtures/api/feeds.json",
        "logos": "../fixtures/api/logos.json",
        "aliases": "../fixtures/aliases.json",
    },
    "failed": [],
}

class BuildTests(unittest.TestCase):
    def build(self, threshold=400000):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        out = Path(tmp.name)
        result = build_source(SOURCE, ROOT / "pipeline" / "config", out, NOW, threshold)
        return out / "fixture", result

    def test_build_artifacts(self):
        base, result = self.build()
        for name in ["latest.json", "catalog.json", "epg.json", "coverage.json"]:
            self.assertTrue((base / name).exists(), name)
        self.assertEqual(result["channels"], 7)
        self.assertEqual(result["mapped"], 5)
        self.assertEqual(result["withPrograms"], 4)
        self.assertEqual(validate(base), [])

    def test_catalog_metadata_and_logo_priority(self):
        base, _ = self.build()
        catalog = json.loads((base / "catalog.json").read_text())
        self.assertEqual(catalog["channels"]["A.us@SD"]["logo"], "https://example.invalid/a.png")
        self.assertEqual(catalog["channels"]["C.us@SD"]["logo"], "https://example.invalid/c.png")
        self.assertEqual(catalog["channels"]["B.us@SD"]["logo"], "https://example.invalid/b-from-logos.png")
        self.assertEqual(catalog["channels"]["F.us@SD"]["logo"], "https://example.invalid/f-alias.png")
        self.assertFalse(catalog["channels"]["B.us@SD"]["hasEpg"])
        self.assertEqual(catalog["streamMap"]["https://example.invalid/c2.m3u8"], "C.us@SD")
        self.assertNotIn("D.us@SD", catalog["channels"])

    def test_epg_no_stop_and_coverage(self):
        base, _ = self.build()
        epg = json.loads((base / "epg.json").read_text())
        self.assertEqual(epg["channels"]["C.us@SD"]["unknownDurationCount"], 1)
        self.assertNotIn("e", epg["channels"]["C.us@SD"]["programs"][0])
        current = [p for p in epg["channels"]["A.us@SD"]["programs"] if p["s"] <= NOW < p.get("e", NOW)]
        self.assertEqual(current[0]["t"], "Alpha Today")
        coverage = json.loads((base / "coverage.json").read_text())
        self.assertEqual(coverage["totals"]["withPrograms"], 4)
        self.assertEqual(coverage["totals"]["withoutPrograms"], 1)
        self.assertEqual(coverage["totals"]["notMapped"], 1)
        self.assertAlmostEqual(coverage["coverage"]["effective"], 4 / 7)

    def test_shards(self):
        base, _ = self.build(threshold=100)
        manifest = json.loads((base / "latest.json").read_text())
        self.assertTrue(manifest["epg"]["sharded"])
        self.assertGreater(len(manifest["epg"]["files"]), 1)
        self.assertFalse((base / "epg.json").exists())
        self.assertEqual(validate(base), [])

    def test_deterministic(self):
        base1, _ = self.build()
        base2, _ = self.build()
        m1 = json.loads((base1 / "latest.json").read_text())
        m2 = json.loads((base2 / "latest.json").read_text())
        self.assertEqual(m1["catalog"]["hash"], m2["catalog"]["hash"])
        self.assertEqual(m1["epg"]["hash"], m2["epg"]["hash"])

if __name__ == "__main__":
    unittest.main()
