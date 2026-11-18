#!/usr/bin/env python3
"""Read-only check of the Presentation localization resources in a built app."""
import pathlib
import plistlib
import subprocess
import sys

BUNDLE = "SchneeGlassKit_SchneeGlassPresentation.bundle"
LANGUAGES = ("en", "ja")
TABLE = "GlassStatus.strings"
SOURCE = (
    pathlib.Path(__file__).resolve().parents[1]
    / "Packages/SchneeGlassKit/Sources/SchneeGlassPresentation/Resources"
)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def real_directory(path):
    return path.is_dir() and not path.is_symlink()


def read_table(path):
    require(path.is_file() and not path.is_symlink(), f"Missing or linked table: {path}")
    result = subprocess.run(
        ["plutil", "-convert", "xml1", "-o", "-", str(path.absolute())],
        check=True,
        stdout=subprocess.PIPE,
    )
    value = plistlib.loads(result.stdout)
    require(
        isinstance(value, dict)
        and bool(value)
        and all(isinstance(k, str) and isinstance(v, str) and v for k, v in value.items()),
        f"Invalid localization table: {path}",
    )
    return value


def verify(app, source=SOURCE):
    require(app.suffix == ".app" and real_directory(app), "Expected a real .app directory")
    contents = app / "Contents"
    resources = contents / "Resources"
    bundle = resources / BUNDLE
    for path in (contents, resources, bundle):
        require(real_directory(path), f"Missing or linked directory: {path}")

    info = contents / "Info.plist"
    require(info.is_file() and not info.is_symlink(), "Missing or linked app Info.plist")
    with info.open("rb") as file:
        metadata = plistlib.load(file)
    require(isinstance(metadata, dict), "Invalid app Info.plist dictionary")
    languages = metadata.get("CFBundleLocalizations")
    require(
        isinstance(languages, list)
        and len(languages) == len(LANGUAGES)
        and all(isinstance(language, str) for language in languages)
        and set(languages) == set(LANGUAGES),
        "App CFBundleLocalizations must declare exactly en and ja",
    )

    # Xcode may emit a standard macOS resource bundle or a flat bundle.
    candidates = (bundle / "Contents" / "Resources", bundle)
    roots = [
        root for root in candidates
        if any((root / f"{lang}.lproj").exists() for lang in LANGUAGES)
    ]
    require(len(roots) == 1, "Expected exactly one localization resource root")
    root = roots[0]
    if root != bundle:
        require(real_directory(bundle / "Contents"), "Linked bundle Contents")
        require(real_directory(root), "Linked bundle Resources")

    expected = {}
    for language in LANGUAGES:
        locale_dir = root / f"{language}.lproj"
        require(real_directory(locale_dir), f"Missing or linked locale: {language}")
        expected[language] = read_table(source / f"{language}.lproj" / TABLE)
        actual = read_table(locale_dir / TABLE)
        require(actual == expected[language], f"Packaged translation mismatch: {language}")

    require(expected["en"].keys() == expected["ja"].keys(), "Source key sets differ")
    print(f"Verified packaged localization: {len(expected['en'])} keys x 2 languages")


if __name__ == "__main__":
    try:
        require(len(sys.argv) == 2, "usage: verify-localization-bundle.py <SchneeGlass.app>")
        verify(pathlib.Path(sys.argv[1]))
    except (ValueError, OSError, subprocess.CalledProcessError, plistlib.InvalidFileException) as error:
        sys.exit(f"Localization bundle verification failed: {error}")
