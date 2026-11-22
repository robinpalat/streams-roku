import os
import unittest
from unittest import mock

from pipeline.pages import (
    PagesConfigError,
    normalize_meta_path,
    pages_base,
    parse_repo_slug,
    public_path,
    resolve_repo_slug,
    site_base,
)


class PagesUrlTests(unittest.TestCase):
    def test_repo_url_variants(self):
        for value in [
            "https://github.com/robinpalat/streams.git",
            "https://github.com/robinpalat/streams",
            "git@github.com:robinpalat/streams.git",
            "ssh://git@github.com/robinpalat/streams.git",
            "robinpalat/streams",
        ]:
            self.assertEqual(parse_repo_slug(value), "robinpalat/streams")

    def test_pages_url_keeps_repository_prefix(self):
        self.assertEqual(
            pages_base("robinpalat/streams", "/real/"),
            "https://robinpalat.github.io/streams/real/",
        )
        self.assertEqual(
            site_base("robinpalat/streams"),
            "https://robinpalat.github.io/streams/",
        )
        self.assertEqual(public_path("robinpalat/streams"), "/real/")
        self.assertEqual(
            pages_base("robinpalat/streams", "real"),
            "https://robinpalat.github.io/streams/real/",
        )

    def test_user_site_has_no_repo_prefix(self):
        self.assertEqual(
            pages_base("robinpalat/robinpalat.github.io", "/real/"),
            "https://robinpalat.github.io/real/",
        )

    def test_meta_path_normalization(self):
        self.assertEqual(normalize_meta_path("real"), "/real/")
        self.assertEqual(normalize_meta_path("/real/"), "/real/")

    def test_invalid_repositories(self):
        for value in ["", "https://github.com/only-owner", "owner/name/extra", "bad repo/name"]:
            with self.assertRaises(PagesConfigError):
                parse_repo_slug(value)

    def test_resolve_from_environment(self):
        with mock.patch.dict(os.environ, {"GITHUB_REPOSITORY": "robinpalat/streams"}, clear=False):
            self.assertEqual(resolve_repo_slug(), "robinpalat/streams")


if __name__ == "__main__":
    unittest.main()
