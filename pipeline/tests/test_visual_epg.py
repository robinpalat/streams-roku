import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class EpgVisualTests(unittest.TestCase):
    def setUp(self):
        self.brs = (ROOT / "components" / "EpgGrid.brs").read_text()
        self.xml = (ROOT / "components" / "EpgGrid.xml").read_text()

    def test_temporal_geometry_is_unchanged(self):
        for token in [
            "m.timeX = 200",
            "m.timeW = 1040",
            "m.rowTop = 100",
            "m.rowH = 74",
            "m.visibleRows = 6",
            "m.windowMinutes = 240",
        ]:
            self.assertIn(token, self.brs)
        self.assertIn("(ps - m.windowStart) / 60 / m.windowMinutes", self.brs)
        self.assertIn("line.height = m.visibleRows * m.rowH", self.brs)
        self.assertIn("return m.windowStart + (m.windowMinutes * 60)", self.brs)

    def test_typography_scale_and_palette_are_applied(self):
        for token in [
            "font:SmallestSystemFont",
            "font:SmallSystemFont",
            "font:MediumSystemFont",
            "0x0A1419FF",
            "0x1E4A47FF",
            "0x2A5C66FF",
            "0xB97C6EFF",
        ]:
            self.assertIn(token, self.brs + self.xml)
        for old_color in ["0x3A6EA5FF", "0x2F5B3AFF", "0xE05555FF", "0x252D38FF"]:
            self.assertNotIn(old_color, self.brs + self.xml)

    def test_detail_panel_fits_above_help_without_overlap(self):
        self.assertIn('translation="[20,550]" width="1240" height="120"', self.xml)
        self.assertIn('translation="[36,580]" width="390" height="44"', self.xml)
        self.assertIn('translation="[450,560]" width="790" height="78"', self.xml)
        self.assertIn('translation="[36,650]" width="1180" height="16"', self.xml)
        self.assertIn('translation="[30,682]" width="1220" height="18"', self.xml)

    def test_cell_text_is_guarded_by_ellipsis(self):
        self.assertIn("function Ellipsize(", self.brs)
        self.assertIn("name.text = Ellipsize(ch.name, 24)", self.brs)
        self.assertIn("title.text = Ellipsize(p.t, maxChars)", self.brs)
        self.assertIn("timeLabel.text = Ellipsize(EpgTimeRange(p.s, progEnd), maxTimeChars)", self.brs)

    def test_taller_rows_fit_channel_and_cell_content(self):
        self.assertIn("name.translation = [84, y + 15]", self.brs)
        self.assertIn("name.height = 44", self.brs)
        self.assertIn("name.wrap = true", self.brs)
        self.assertIn('name.vertAlign = "center"', self.brs)
        self.assertIn("logo.translation = [30, y + 22]", self.brs)
        self.assertIn("block.translation = [x, y + 7]", self.brs)
        self.assertIn("rect.height = m.rowH - 14", self.brs)
        self.assertIn("mark.height = m.rowH - 14", self.brs)
        self.assertIn("title.translation = [8, 8]", self.brs)
        self.assertIn("title.height = 24", self.brs)
        self.assertIn("timeLabel.translation = [8, 33]", self.brs)
        self.assertIn("timeLabel.height = 18", self.brs)

    def test_six_rows_fit_between_grid_and_detail_panel(self):
        self.assertIn("m.rowTop = 100", self.brs)
        self.assertIn("m.rowH = 74", self.brs)
        self.assertIn("m.visibleRows = 6", self.brs)
        self.assertLessEqual(100 + 6 * 74, 548)
        self.assertIn('translation="[20,548]" width="1240" height="1"', self.xml)
        self.assertIn('translation="[20,550]" width="1240" height="120"', self.xml)
        self.assertIn('translation="[30,682]" width="1220" height="18"', self.xml)


if __name__ == "__main__":
    unittest.main()
