#!/usr/bin/env python3
"""Vérifie qu'un DOCX produit par Andika s'ouvre : archive valide, lecture par python-docx,
et, si LibreOffice est présent, conversion en texte avec le contenu attendu.

Usage : check_docx.py <dossier des échantillons>
"""
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile

import docx


def main(folder):
    errors = []
    plain = os.path.join(folder, "echantillon.docx")
    stamped = os.path.join(folder, "echantillon-horodate.docx")
    for path in (plain, stamped):
        if not os.path.exists(path):
            errors.append(f"échantillon absent : {path}")
    if errors:
        return errors

    for path in (plain, stamped):
        z = zipfile.ZipFile(path)
        bad = z.testzip()
        if bad:
            errors.append(f"{path} : entrée corrompue {bad}")
        if z.namelist()[0] != "[Content_Types].xml":
            errors.append(f"{path} : [Content_Types].xml n'est pas la première entrée")

    d = docx.Document(plain)
    if d.paragraphs[0].text != "Entretien — Parc National de la Lomami":
        errors.append(f"titre inattendu : {d.paragraphs[0].text!r}")
    if d.paragraphs[0].style.name != "Title":
        errors.append(f"style du titre : {d.paragraphs[0].style.name}")
    body = "\n".join(p.text for p in d.paragraphs[2:])
    for expected in ("Segment numéro 0 :", "le parc & ses « habitants » <test> déjà là.", "Segment numéro 39"):
        if expected not in body:
            errors.append(f"texte absent : {expected}")
    print(f"{len(d.paragraphs)} paragraphes dans l'échantillon simple")

    h = docx.Document(stamped)
    texts = [p.text for p in h.paragraphs]
    if "[0:00] Bonjour à tous & bienvenue." not in texts:
        errors.append(f"horodatage absent : {texts}")
    if not h.paragraphs[1].runs[0].bold:
        errors.append("l'heure n'est pas en gras")

    soffice = shutil.which("soffice") or shutil.which("libreoffice")
    if soffice:
        with tempfile.TemporaryDirectory() as out:
            for path in (plain, stamped):
                subprocess.run(
                    [soffice, "--headless", "--convert-to", "txt:Text", "--outdir", out, path],
                    check=True, capture_output=True, timeout=180,
                )
            text = open(os.path.join(out, "echantillon.txt"), encoding="utf-8-sig").read()
            if "Entretien — Parc National de la Lomami" not in text or "Segment numéro 39" not in text:
                errors.append("LibreOffice n'a pas relu le texte attendu")
            else:
                print("LibreOffice : conversion en texte réussie")
    else:
        print("LibreOffice absent : contrôle de conversion ignoré")
    return errors


if __name__ == "__main__":
    errs = main(sys.argv[1])
    for e in errs:
        print("ERREUR :", e)
    sys.exit(1 if errs else 0)
