#!/usr/bin/env python3
"""Calcule le taux d'erreurs sur les mots (WER) entre un texte de référence et
une transcription. Usage : python3 tools/wer.py reference.txt transcription.txt

Le texte est normalisé : minuscules, accents conservés, ponctuation retirée.
"""
import re
import sys
import unicodedata


def normaliser(texte: str) -> list:
    texte = unicodedata.normalize("NFC", texte).lower()
    texte = texte.replace("’", "'")
    texte = re.sub(r"[^\w\s']", " ", texte, flags=re.UNICODE)
    texte = texte.replace("_", " ")
    return texte.split()


def distance(ref: list, hyp: list) -> int:
    """Distance de Levenshtein au niveau des mots."""
    precedent = list(range(len(hyp) + 1))
    for i, mot_ref in enumerate(ref, start=1):
        courant = [i]
        for j, mot_hyp in enumerate(hyp, start=1):
            cout = 0 if mot_ref == mot_hyp else 1
            courant.append(
                min(precedent[j] + 1, courant[j - 1] + 1, precedent[j - 1] + cout)
            )
        precedent = courant
    return precedent[-1]


def wer(reference: str, transcription: str) -> float:
    ref = normaliser(reference)
    hyp = normaliser(transcription)
    if not ref:
        return 0.0 if not hyp else 1.0
    return distance(ref, hyp) / len(ref)


def main(argv: list) -> int:
    if len(argv) != 3:
        print(__doc__)
        return 2
    with open(argv[1], encoding="utf-8") as f:
        reference = f.read()
    with open(argv[2], encoding="utf-8") as f:
        transcription = f.read()
    print("WER = {:.1%}".format(wer(reference, transcription)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
