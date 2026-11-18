#!/usr/bin/env python3
"""Contrôles de cohérence entre les fichiers du projet (sans SDK Flutter).

1. Chaque import relatif Dart pointe vers un fichier existant.
2. Chaque import `package:andika/...` des tests pointe vers un fichier existant.
3. Chaque méthode appelée côté Dart sur le canal existe dans le sélecteur Kotlin.
4. Les composants du manifeste (service, activité) ont leur classe Kotlin.
5. Les clés de chaînes utilisées existent en français et en anglais.
"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
errors = []


def read(path):
    with open(os.path.join(ROOT, path), encoding="utf-8") as f:
        return f.read()


dart_files = glob.glob(os.path.join(ROOT, "lib/**/*.dart"), recursive=True) + glob.glob(
    os.path.join(ROOT, "test/**/*.dart"), recursive=True
)

# 1 et 2
for path in dart_files:
    text = open(path, encoding="utf-8").read()
    for imp in re.findall(r"^import '([^']+)';", text, re.M):
        if imp.startswith("package:andika/"):
            target = os.path.join(ROOT, "lib", imp[len("package:andika/"):])
        elif imp.startswith("dart:") or imp.startswith("package:"):
            continue
        else:
            target = os.path.normpath(os.path.join(os.path.dirname(path), imp))
        if not os.path.exists(target):
            errors.append(f"import introuvable : {os.path.relpath(path, ROOT)} -> {imp}")

# 3
bridge = read("lib/platform/platform_bridge.dart")
dart_methods = set(re.findall(r"invokeMethod[^(]*\(\s*'(\w+)'", bridge))
for path in dart_files:
    text = open(path, encoding="utf-8").read()
    dart_methods |= set(re.findall(r"\.invoke<[^>]*>\(\s*'(\w+)'", text))
kotlin = read("android/app/src/main/kotlin/org/chadracklonde/andika/PlatformBridge.kt")
kotlin_methods = set(re.findall(r'^\s+"(\w+)"\s*->', kotlin, re.M))
for m in sorted(dart_methods - kotlin_methods):
    errors.append(f"méthode appelée côté Dart mais absente de Kotlin : {m}")
for m in sorted(kotlin_methods - dart_methods):
    print(f"info : méthode Kotlin jamais appelée côté Dart : {m}")

# 4
manifest = read("android/app/src/main/AndroidManifest.xml")
for name in re.findall(r'android:name="\.(\w+)"', manifest):
    if not os.path.exists(
        os.path.join(ROOT, f"android/app/src/main/kotlin/org/chadracklonde/andika/{name}.kt")
    ):
        errors.append(f"classe du manifeste introuvable : {name}")
for res in re.findall(r"@xml/(\w+)", manifest):
    if not os.path.exists(os.path.join(ROOT, f"android/app/src/main/res/xml/{res}.xml")):
        errors.append(f"ressource xml introuvable : {res}")

# 5
src = read("lib/app/strings.dart")
fr = src.split("const Map<String, String> kStringsFr")[1].split("const Map<String, String> kStringsEn")[0]
en = src.split("const Map<String, String> kStringsEn")[1]
keys = lambda t: set(re.findall(r"^  '([a-z_0-9]+)':", t, re.M))
F, E = keys(fr), keys(en)
if F != E:
    errors.append(f"clés différentes entre FR et EN : {sorted(F ^ E)}")
for path in dart_files:
    if path.endswith("strings.dart") or "/test/" in path:
        continue
    text = open(path, encoding="utf-8").read()
    for k in set(re.findall(r"\bs\.t\('([a-z_0-9]+)'", text)):
        if k not in F:
            errors.append(f"clé de texte manquante : {k} ({os.path.relpath(path, ROOT)})")

if errors:
    print("\n".join(errors))
    print(f"{len(errors)} problème(s)")
    sys.exit(1)
print("cohérence : aucun problème détecté")
