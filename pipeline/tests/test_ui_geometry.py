import re
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

class LogogeometryTests(unittest.TestCase):
    def test_channel_item_fixed_logo_box(self):
        tree = ET.parse(ROOT / "components" / "ChannelItem.xml")
        root = tree.getroot()
        ch = root.find("./children")
        self.assertIsNotNone(ch)
        poster = ch.find("Poster[@id='logo']")
        self.assertIsNotNone(poster)
        self.assertEqual(poster.attrib.get("width"), "58")
        self.assertEqual(poster.attrib.get("height"), "36")
        self.assertEqual(poster.attrib.get("loadWidth"), "58")
        self.assertEqual(poster.attrib.get("loadHeight"), "36")
        self.assertEqual(poster.attrib.get("loadDisplayMode"), "limitSize")
        self.assertEqual(poster.attrib.get("translation"), "[8,4]")
        # 4 + 36 = 40, inside the 44 px row; no vertical overlap.
        self.assertLessEqual(4 + 36, 44)
        name = ch.find("Label[@id='name']")
        self.assertIsNotNone(name)
        self.assertEqual(name.attrib.get("translation"), "[76,10]")

    def test_markup_list_uses_item_component(self):
        tree = ET.parse(ROOT / "components" / "MainScene.xml")
        node = tree.getroot().find(".//MarkupList[@id='list']")
        self.assertIsNotNone(node)
        self.assertEqual(node.attrib.get("itemComponentName"), "ChannelItem")
        self.assertEqual(node.attrib.get("itemSize"), "[790,44]")
        self.assertEqual(node.attrib.get("itemSpacing"), "[0,4]")
        self.assertIsNone(tree.getroot().find(".//LabelList"))

    def test_no_native_icon_attributes_remain(self):
        text = (ROOT / "components" / "MainScene.brs").read_text(encoding="utf-8")
        self.assertNotIn("HDListItemIconURL", text)
        self.assertNotIn("HDListItemIconSelectedURL", text)

    def test_centering_logic_exists(self):
        text = (ROOT / "components" / "ChannelItem.brs").read_text(encoding="utf-8")
        self.assertIn("bitmapWidth", text)
        self.assertIn("bitmapHeight", text)
        self.assertIn("FitLogoInBox", text)
        self.assertIn("m.logo.translation", text)

if __name__ == "__main__":
    unittest.main()
