import json
import shutil
import tempfile
import unittest
from pathlib import Path

from pipeline.build import ROOT, build_source
from pipeline.publish import (
    PublicationError,
    _assert_no_sensitive,
    check_publication_guard,
    prepare,
    validate_public,
)
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


class PublishTests(unittest.TestCase):
    def build(self, threshold=400000):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        out = Path(tmp.name) / "out"
        result = build_source(SOURCE, ROOT / "pipeline" / "config", out, NOW, threshold)
        return out / "fixture", result

    def test_public_artifact_is_minimal_and_valid(self):
        source, _ = self.build()
        with tempfile.TemporaryDirectory() as tmp:
            dest = Path(tmp) / "site"
            prepare(source, dest)
            self.assertTrue((dest / "index.html").exists())
            self.assertTrue((dest / "real" / "latest.json").exists())
            self.assertEqual(validate(dest / "real"), [])
            validate_public(dest)
            catalog = json.loads((dest / "real" / "catalog.json").read_text())
            self.assertNotIn("streamMap", catalog)
            self.assertNotIn("c2.m3u8", (dest / "real" / "catalog.json").read_text())
            manifest = json.loads((dest / "real" / "latest.json").read_text())
            for key in ["catalog", "epg", "coverage"]:
                self.assertIn(key, manifest)
            coverage = json.loads((dest / "real" / "coverage.json").read_text())
            self.assertNotIn("sourceErrors", coverage)

    def test_rerun_with_previous_publication(self):
        source, _ = self.build()
        with tempfile.TemporaryDirectory() as tmp:
            dest = Path(tmp) / "site"
            prepare(source, dest)
            prepare(source, dest, previous=dest)
            validate_public(dest)

    def test_sharded_epg_is_published_without_source_files(self):
        source, _ = self.build(threshold=100)
        with tempfile.TemporaryDirectory() as tmp:
            dest = Path(tmp) / "site"
            prepare(source, dest)
            manifest = json.loads((dest / "real" / "latest.json").read_text())
            self.assertTrue(manifest["epg"].get("sharded"))
            self.assertFalse((dest / "real" / "epg.json").exists())
            for entry in manifest["epg"]["files"]:
                self.assertTrue((dest / "real" / entry["file"]).exists())
            validate_public(dest)

    def test_guard_blocks_lost_programming(self):
        previous = {
            "totals": {"withPrograms": 2},
            "channels": {
                "A": {"status": "with_programs", "programCount": 3},
                "B": {"status": "with_programs", "programCount": 2},
            },
        }
        new = {
            "totals": {"withPrograms": 1},
            "channels": {
                "A": {"status": "with_programs", "programCount": 3},
                "B": {"status": "without_programs", "programCount": 0},
            },
        }
        epg = {"channels": {"A": {"programs": [{"s": 1}]}, "B": {"programs": []}}}
        with self.assertRaises(PublicationError):
            check_publication_guard(new, epg, previous, min_coverage_ratio=0.1,
                                     min_program_ratio=0.1)
        check_publication_guard(new, epg, previous, min_coverage_ratio=0.1,
                                 min_program_ratio=0.1, allow_channel_loss=True)

    def test_guard_blocks_empty_or_anomalous_generation(self):
        previous = {"totals": {"withPrograms": 2}, "channels": {
            "A": {"status": "with_programs", "programCount": 5},
            "B": {"status": "with_programs", "programCount": 5},
        }}
        with self.assertRaises(PublicationError):
            check_publication_guard({"totals": {"withPrograms": 0}, "channels": {}},
                                     {"channels": {}}, previous)
        degraded = {"totals": {"withPrograms": 2}, "channels": {
            "A": {"status": "with_programs", "programCount": 1},
            "B": {"status": "with_programs", "programCount": 1},
        }}
        with self.assertRaises(PublicationError):
            check_publication_guard(
                degraded,
                {"channels": {"A": {"programs": [{}]}, "B": {"programs": [{}]}}},
                previous, min_coverage_ratio=0.1, min_program_ratio=0.9,
            )

    def test_failed_generation_keeps_previous_destination(self):
        with tempfile.TemporaryDirectory() as tmp:
            dest = Path(tmp) / "site"
            dest.mkdir()
            sentinel = dest / "KEEP"
            sentinel.write_text("previous")
            with self.assertRaises(Exception):
                prepare(Path(tmp) / "missing-source", dest)
            self.assertEqual(sentinel.read_text(), "previous")

    def test_regression_guard_keeps_previous_publication(self):
        source, _ = self.build()
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            dest = tmp / "site"
            prepare(source, dest)
            before = (dest / "real" / "latest.json").read_bytes()
            bad = tmp / "bad"
            shutil.copytree(source, bad)
            (bad / "coverage.json").write_text(json.dumps({
                "schema": 1, "sourceId": "fixture", "generatedAt": NOW,
                "totals": {"withPrograms": 0}, "coverage": {"effective": 0},
                "channels": {},
            }))
            (bad / "epg.json").write_text(json.dumps({"channels": {}}))
            with self.assertRaises(PublicationError):
                prepare(bad, dest, previous=dest)
            self.assertEqual((dest / "real" / "latest.json").read_bytes(), before)

    def test_sensitive_values_are_rejected(self):
        for value in [
            {"streamMap": {"https://private.example/a.m3u8": "A"}},
            {"token": "secret"},
            {"nested": [{"note": "http://192.168.1.7:8001/real/"}]},
        ]:
            with self.assertRaises(PublicationError):
                _assert_no_sensitive(value)


if __name__ == "__main__":
    unittest.main()
