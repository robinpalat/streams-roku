import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

class AppConfigTests(unittest.TestCase):
    def test_generated_base_matches_central_config(self):
        cfg = json.loads((ROOT / "pipeline" / "config" / "roku.generated.json").read_text())
        brs = (ROOT / "source" / "app_config.brs").read_text()
        self.assertIn(f'return "{cfg["metaBase"]}"', brs)
        self.assertIn("/real/", cfg["metaBase"])
        self.assertIn(f'return "{cfg["sourceMatch"]}"', brs)
        self.assertEqual(cfg["profile"], "production")
        self.assertEqual(cfg["repo"], "robinpalat/streams-roku")
        self.assertEqual(cfg["metaBase"], "https://robinpalat.github.io/streams-roku/real/")
        self.assertTrue(cfg["metaBase"].startswith("https://"))
        self.assertNotIn("192.168.1.7", brs)
        self.assertNotIn("8001", brs)

    def test_no_ip_hardcoded_in_app_logic(self):
        # Existing M3U sources may contain their historical LAN URL; metadata
        # configuration must not be duplicated there. The generated app_config
        # is the single source for the metadata URL.
        for name in ["components/MainScene.brs", "components/EpgGrid.brs"]:
            text = (ROOT / name).read_text()
            self.assertNotIn("192.168.1.7", text, name)
            self.assertNotIn("8001", text, name)
        self.assertNotIn("DefaultMetaBase() as String\n    return \"http", (ROOT / "source/util.brs").read_text())
        central = json.loads((ROOT / "pipeline" / "config" / "roku.json").read_text())
        self.assertEqual(central.get("host", ""), "")

    @unittest.skipUnless((ROOT / "pipeline" / "server" / "roku-epg.service.generated").exists(),
                         "local development service not generated")
    def test_service_unit(self):
        cfg = json.loads((ROOT / "pipeline" / "config" / "roku.json").read_text())
        artifacts = (ROOT / cfg["artifactsDir"]).resolve()
        unit = (ROOT / "pipeline" / "server" / "roku-epg.service.generated").read_text()
        self.assertIn(f"--port {cfg['port']}", unit)
        self.assertIn("--bind 0.0.0.0", unit)
        self.assertIn(str(artifacts), unit)
        self.assertIn("Restart=on-failure", unit)

    def test_auto_meta_migration_and_fallback(self):
        util = (ROOT / "source" / "util.brs").read_text()
        scene = (ROOT / "components" / "MainScene.brs").read_text()
        self.assertIn("IsConfiguredMetaSource", util)
        self.assertIn("s.meta = DefaultMetaBase()", util)
        self.assertIn("IsLegacyLocalMeta(s.meta)", util)
        self.assertIn("if IsConfiguredMetaSource(src.url) then return DefaultMetaBase()", scene)

    def test_guide_is_present_and_wired(self):
        xml = (ROOT / "components" / "MainScene.xml").read_text()
        self.assertIn('<EpgGrid id="guide"', xml)
        scene = (ROOT / "components" / "MainScene.brs").read_text()
        self.assertIn('kind: "guide"', scene)
        self.assertIn("OpenGuide()", scene)
        self.assertIn('m.guide.observeField("close"', scene)

    def test_grid_static_geometry_and_navigation(self):
        brs = (ROOT / "components" / "EpgGrid.brs").read_text()
        xml = (ROOT / "components" / "EpgGrid.xml").read_text()
        self.assertIn("m.windowMinutes = 240", brs)
        self.assertIn("m.visibleRows = 6", brs)
        self.assertIn("removeChildrenIndex", brs)
        for key in ['key = "up"', 'key = "down"', 'key = "left"', 'key = "right"', 'key = "back"']:
            self.assertIn(key, brs)
        self.assertIn('key = "play" or key = "OK"', brs)
        self.assertIn('id="gridLayer"', xml)
        self.assertIn('id="detailTitle"', xml)
        self.assertIn('id="help"', xml)
    def test_development_profile_remains_available(self):
        configure = (ROOT / "pipeline" / "configure.py").read_text()
        self.assertIn('choices=["development", "production"]', configure)
        self.assertIn('base = f"http://{host}:{port}{meta_path}"', configure)
        self.assertIn("write_service(port, artifacts)", configure)


if __name__ == "__main__":
    unittest.main()
