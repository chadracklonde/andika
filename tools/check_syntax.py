#!/usr/bin/env python3
"""Contrôle de syntaxe (pas de types) des fichiers Dart et Kotlin avec tree-sitter.

Sert quand Flutter et le SDK Android ne sont pas disponibles. Ne remplace pas
`flutter analyze` ni la compilation Gradle.

Installation : pip install tree-sitter tree-sitter-language-pack
Usage       : python3 tools/check_syntax.py [dossier ...]
"""
import os
import sys

from tree_sitter_language_pack import get_parser

LANGS = {".dart": "dart", ".kt": "kotlin"}


def erreurs(noeud, source, acc):
    if noeud.type == "ERROR" or noeud.is_missing:
        ligne = noeud.start_point[0] + 1
        extrait = source[noeud.start_byte:noeud.end_byte][:60].decode("utf-8", "replace")
        acc.append((ligne, noeud.type if noeud.type == "ERROR" else "MANQUE " + noeud.type, extrait))
        return
    for enfant in noeud.children:
        erreurs(enfant, source, acc)


def main(racines):
    parsers = {}
    total = 0
    mauvais = 0
    for racine in racines:
        for dossier, _, fichiers in os.walk(racine):
            if any(p in dossier for p in ("/build", "/.dart_tool", "/third_party", "/.git")):
                continue
            for nom in sorted(fichiers):
                ext = os.path.splitext(nom)[1]
                if ext not in LANGS:
                    continue
                chemin = os.path.join(dossier, nom)
                langue = LANGS[ext]
                if langue not in parsers:
                    parsers[langue] = get_parser(langue)
                with open(chemin, "rb") as f:
                    source = f.read()
                arbre = parsers[langue].parse(source)
                acc = []
                erreurs(arbre.root_node, source, acc)
                total += 1
                if acc:
                    mauvais += 1
                    for ligne, genre, extrait in acc[:5]:
                        print("{}:{}: {} près de {!r}".format(chemin, ligne, genre, extrait))
    print("{} fichier(s) contrôlé(s), {} avec erreur de syntaxe".format(total, mauvais))
    return 1 if mauvais else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:] or ["lib", "test", "android"]))
