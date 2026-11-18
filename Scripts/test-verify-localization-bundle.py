#!/usr/bin/env python3
"""Exercise the localization bundle guard with synthetic app bundles."""
import pathlib
import plistlib
import runpy
import tempfile
import unittest

MODULE = runpy.run_path(str(pathlib.Path(__file__).with_name("verify-localization-bundle.py")))
VERIFY = MODULE["verify"]
BUNDLE = MODULE["BUNDLE"]
TABLE = MODULE["TABLE"]


class LocalizationBundleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = pathlib.Path(self.temp.name)
        self.app = root / "SchneeGlass.app"
        self.source = root / "source"
        self.bundle = self.app / "Contents" / "Resources" / BUNDLE
        self.resources = self.bundle / "Contents" / "Resources"
        self.write_info({"CFBundleLocalizations": ["en", "ja"]})
        self.write(self.source, "en", {"connected": "Connected"})
        self.write(self.source, "ja", {"connected": "接続済み"})

    def write_info(self, values):
        path = self.app / "Contents" / "Info.plist"
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("wb") as file:
            plistlib.dump(values, file, fmt=plistlib.FMT_BINARY)
        return path

    def write(self, root, language, values):
        path = root / f"{language}.lproj" / TABLE
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("wb") as file:
            plistlib.dump(values, file, fmt=plistlib.FMT_BINARY)
        return path

    def populate(self, root):
        self.write(root, "en", {"connected": "Connected"})
        self.write(root, "ja", {"connected": "接続済み"})

    def test_standard_bundle(self):
        self.populate(self.resources)
        VERIFY(self.app, self.source)

    def test_flat_bundle(self):
        self.populate(self.bundle)
        VERIFY(self.app, self.source)

    def test_missing_language(self):
        self.write(self.resources, "en", {"connected": "Connected"})
        with self.assertRaisesRegex(ValueError, "Missing or linked locale"):
            VERIFY(self.app, self.source)

    def test_changed_translation(self):
        self.populate(self.resources)
        self.write(self.resources, "ja", {"connected": "Different"})
        with self.assertRaisesRegex(ValueError, "Packaged translation mismatch"):
            VERIFY(self.app, self.source)

    def test_linked_table(self):
        self.populate(self.resources)
        path = self.resources / "ja.lproj" / TABLE
        path.unlink()
        path.symlink_to(self.source / "ja.lproj" / TABLE)
        with self.assertRaisesRegex(ValueError, "Missing or linked table"):
            VERIFY(self.app, self.source)

    def test_ambiguous_bundle_layout(self):
        self.populate(self.resources)
        self.populate(self.bundle)
        with self.assertRaisesRegex(ValueError, "exactly one localization resource root"):
            VERIFY(self.app, self.source)

    def test_missing_app_language_declaration(self):
        self.populate(self.resources)
        self.write_info({})
        with self.assertRaisesRegex(ValueError, "CFBundleLocalizations"):
            VERIFY(self.app, self.source)

    def test_invalid_app_language_declaration(self):
        self.populate(self.resources)
        for languages in (["en"], ["en", "en"], ["en", "ja", "fr"], "ja", ["en", 1]):
            with self.subTest(languages=languages):
                self.write_info({"CFBundleLocalizations": languages})
                with self.assertRaisesRegex(ValueError, "CFBundleLocalizations"):
                    VERIFY(self.app, self.source)

    def test_linked_app_info(self):
        self.populate(self.resources)
        path = self.app / "Contents" / "Info.plist"
        target = self.source / "Info.plist"
        path.rename(target)
        path.symlink_to(target)
        with self.assertRaisesRegex(ValueError, "Missing or linked app Info.plist"):
            VERIFY(self.app, self.source)

    def test_source_key_set_mismatch(self):
        self.populate(self.resources)
        values = {"connected": "接続済み", "extra": "追加"}
        self.write(self.source, "ja", values)
        self.write(self.resources, "ja", values)
        with self.assertRaisesRegex(ValueError, "Source key sets differ"):
            VERIFY(self.app, self.source)


if __name__ == "__main__":
    unittest.main()
