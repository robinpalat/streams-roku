import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github" / "workflows" / "epg-pages.yml"


class WorkflowTests(unittest.TestCase):
    def setUp(self):
        self.text = WORKFLOW.read_text(encoding="utf-8")

    def test_schedule_and_manual_dispatch(self):
        self.assertIn('cron: "0 */6 * * *"', self.text)
        self.assertIn("workflow_dispatch:", self.text)

    def test_minimal_permissions_and_no_personal_token(self):
        self.assertIn("contents: read", self.text)
        self.assertIn("pages: write", self.text)
        self.assertIn("id-token: write", self.text)
        self.assertNotIn("personal_access_token", self.text.lower())
        self.assertNotIn("secrets.", self.text.lower())
        self.assertIn("cancel-in-progress: false", self.text)

    def test_official_pages_actions_are_used(self):
        for action in [
            "actions/configure-pages@",
            "actions/upload-pages-artifact@",
            "actions/deploy-pages@",
        ]:
            self.assertIn(action, self.text)

    def test_tests_run_before_build_and_deploy(self):
        order = [
            "python3 -m unittest discover",
            "pipeline.fetch_epg",
            "pipeline.build",
            "pipeline.publish",
            "actions/upload-pages-artifact@",
            "actions/deploy-pages@",
        ]
        positions = [self.text.index(token) for token in order]
        self.assertEqual(positions, sorted(positions))

    def test_production_url_and_previous_publication_guard(self):
        self.assertIn("--profile production", self.text)
        self.assertIn("GITHUB_REPOSITORY", self.text)
        self.assertIn("--previous .pages-previous", self.text)
        self.assertIn("coverage.json", self.text)
        self.assertIn("github-pages", self.text)
        self.assertIn("Verify published endpoints", self.text)
        self.assertIn("application/json", self.text)

    def test_grabber_diagnostics_are_uploaded(self):
        self.assertIn("grabber-status.json", self.text)
        self.assertIn("actions/upload-artifact@", self.text)


if __name__ == "__main__":
    unittest.main()
