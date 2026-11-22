import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

class GridCorrectionTests(unittest.TestCase):
    def test_ok_routes_current_program_to_main_scene(self):
        grid = (ROOT / "components" / "EpgGrid.brs").read_text()
        scene = (ROOT / "components" / "MainScene.brs").read_text()
        xml = (ROOT / "components" / "EpgGrid.xml").read_text()
        self.assertIn('id="playRequest"', xml)
        self.assertIn("m.top.playRequest = { url: ch.url", grid)
        self.assertIn("EpgProgramIsCurrent(programs, idx, now)", grid)
        self.assertIn('Programa futuro: OK solo muestra información', grid)
        self.assertIn('No se puede sintonizar: URL no disponible', grid)
        self.assertIn('m.guide.observeField("playRequest"', scene)
        self.assertIn("PlayChannel(ch)", scene)
        self.assertNotIn("PlayChannel(", grid)
        self.assertNotIn("StartPlayback(", grid)

    def test_grid_filters_channels_by_visible_window(self):
        grid = (ROOT / "components" / "EpgGrid.brs").read_text()
        epg = (ROOT / "source" / "epg.brs").read_text()
        self.assertIn("sub BuildVisibleChannels()", grid)
        self.assertIn("EpgProgramsOverlap(progs, ws, we)", grid)
        self.assertIn("m.visibleChannels.Push({ channel: ch, originalIndex: i })", grid)
        self.assertIn("for i = 0 to m.top.channels.Count() - 1", grid)
        self.assertIn("function EpgProgramsOverlap", epg)
        self.assertIn("function EpgProgramIsCurrent", epg)
        self.assertIn("m.visibleChannels", grid)
        self.assertNotIn("m.top.channels = []", grid)
        self.assertNotIn("m.top.channels = m.", grid)

    def test_navigation_uses_visible_list_and_preserves_selection(self):
        grid = (ROOT / "components" / "EpgGrid.brs").read_text()
        self.assertIn("m.row + 1 < m.visibleChannels.Count()", grid)
        self.assertIn("PreserveSelection(oldKey, oldOrig)", grid)
        self.assertIn("NearestVisibleIndex(oldOriginalIndex)", grid)
        self.assertIn("No hay canales con programación en esta ventana", grid)

if __name__ == "__main__":
    unittest.main()
