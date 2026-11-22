import subprocess
import tempfile
import unittest
from pathlib import Path

from pipeline.fetch_epg import fetch


class FetchEpgTests(unittest.TestCase):
    def config(self, tmp: Path):
        channels_ok = tmp / "channels-ok.xml"
        channels_ok.write_text("<channels/>")
        channels_bad = tmp / "channels-bad.xml"
        channels_bad.write_text("<channels/>")
        return {
            "epgRepository": "https://github.com/iptv-org/epg.git",
            "days": 1,
            "timeout": 1000,
            "sources": [
                {"id": "ok", "channels": str(channels_ok), "output": "guide-ok.xml", "required": True},
                {"id": "optional", "channels": str(channels_bad), "output": "guide-optional.xml", "required": False},
            ],
        }

    def sources(self, tmp: Path):
        return {"sources": [
            {"id": "real", "name": "Real", "m3u": "https://example.test/list.m3u", "epg": ["old.xml"], "failed": []}
        ]}

    def test_all_grabbers_are_recorded(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            def runner(repo, channels, output, days, timeout):
                if "bad" in str(channels):
                    return subprocess.CompletedProcess([], 1, "", "site failed")
                output.parent.mkdir(parents=True, exist_ok=True)
                output.write_text("<tv/>")
                return subprocess.CompletedProcess([], 0, "ok", "")
            generated, status, ok = fetch(self.config(tmp), self.sources(tmp), tmp, tmp / "out", runner=runner)
            self.assertTrue(ok)
            self.assertEqual([r["status"] for r in status["sources"]], ["ok", "failed"])
            self.assertEqual(status["sources"][1]["id"], "optional")
            self.assertIn("site failed", status["sources"][1]["error"])
            epg = generated["sources"][0]["epg"]
            self.assertEqual(len(epg), 1)
            self.assertTrue(epg[0].endswith("guide-ok.xml"))
            self.assertTrue(generated["sources"][0]["errors"])

    def test_relative_output_directory_is_resolved(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            cfg = self.config(tmp)
            seen = []
            def runner(repo, channels, output, days, timeout):
                seen.append(output)
                output.parent.mkdir(parents=True, exist_ok=True)
                output.write_text("<tv/>")
                return subprocess.CompletedProcess([], 0, "", "")
            fetch(cfg, self.sources(tmp), tmp, Path("pipeline/out/fetch-relative-test"), runner=runner)
            self.assertTrue(seen and seen[0].is_absolute(), seen)
            self.assertEqual(seen[0].parent, (Path.cwd() / "pipeline/out/fetch-relative-test").resolve())
            import shutil
            shutil.rmtree(Path.cwd() / "pipeline/out/fetch-relative-test", ignore_errors=True)

    def test_public_m3u_override_is_used(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            cfg = self.config(tmp)
            cfg["m3u"] = "https://raw.githubusercontent.com/robinpalat/streams/main/streams.m3u"
            def runner(repo, channels, output, days, timeout):
                output.parent.mkdir(parents=True, exist_ok=True)
                output.write_text("<tv/>")
                return subprocess.CompletedProcess([], 0, "", "")
            generated, _, ok = fetch(cfg, self.sources(tmp), tmp, tmp / "out", runner=runner)
            self.assertTrue(ok)
            self.assertEqual(generated["sources"][0]["m3u"], cfg["m3u"])

    def test_required_failure_blocks_publication(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            def runner(repo, channels, output, days, timeout):
                return subprocess.CompletedProcess([], 1, "", "boom")
            _, status, ok = fetch(self.config(tmp), self.sources(tmp), tmp, tmp / "out", runner=runner)
            self.assertFalse(ok)
            self.assertTrue(all(r["status"] == "failed" for r in status["sources"]))

    def test_missing_optional_channels_does_not_block(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            cfg = self.config(tmp)
            cfg["sources"][1]["channels"] = str(tmp / "missing.xml")
            def runner(repo, channels, output, days, timeout):
                output.parent.mkdir(parents=True, exist_ok=True)
                output.write_text("<tv/>")
                return subprocess.CompletedProcess([], 0, "", "")
            _, status, ok = fetch(cfg, self.sources(tmp), tmp, tmp / "out", runner=runner)
            self.assertTrue(ok)
            self.assertEqual(status["sources"][1]["status"], "failed")


if __name__ == "__main__":
    unittest.main()
