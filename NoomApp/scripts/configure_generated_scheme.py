#!/usr/bin/env python3
"""Keep the shared app scheme's CocoaPods build ordering reproducible."""

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
PODS_PROJECT = ROOT / "Pods/Pods.xcodeproj/project.pbxproj"
SCHEME = ROOT / "NoomApp.xcodeproj/xcshareddata/xcschemes/NoomApp.xcscheme"

pods_text = PODS_PROJECT.read_text()
match = re.search(
    r"([A-F0-9]+) /\* Pods-NoomApp \*/ = \{\n\s*isa = PBXNativeTarget;",
    pods_text,
)
if match is None:
    raise SystemExit("Pods-NoomApp target not found after pod install")

target_id = match.group(1)
scheme_text = SCHEME.read_text()
if 'BlueprintName = "Pods-NoomApp"' in scheme_text:
    raise SystemExit(0)

marker = "      <BuildActionEntries>\n"
if marker not in scheme_text:
    raise SystemExit("NoomApp scheme has no BuildActionEntries marker")

entry = f'''         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{target_id}"
               BuildableName = "Pods_NoomApp.framework"
               BlueprintName = "Pods-NoomApp"
               ReferencedContainer = "container:Pods/Pods.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
'''
SCHEME.write_text(scheme_text.replace(marker, marker + entry, 1))
