import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(__file__))
from wer import distance, normaliser, wer  # noqa: E402


class TestWer(unittest.TestCase):
    def test_identique(self):
        self.assertEqual(wer("Bonjour à tous", "bonjour a tous".replace("a ", "à ", 1)), 0.0)

    def test_ponctuation_ignoree(self):
        self.assertEqual(wer("Bonjour, le monde !", "bonjour le monde"), 0.0)

    def test_une_substitution(self):
        self.assertAlmostEqual(wer("un deux trois quatre", "un deux cinq quatre"), 0.25)

    def test_une_suppression_une_insertion(self):
        self.assertAlmostEqual(wer("un deux trois", "un trois"), 1 / 3)
        self.assertAlmostEqual(wer("un deux", "un deux trois"), 0.5)

    def test_reference_vide(self):
        self.assertEqual(wer("", ""), 0.0)
        self.assertEqual(wer("", "mot"), 1.0)

    def test_apostrophe(self):
        self.assertEqual(normaliser("L’école d'été"), ["l'école", "d'été"])

    def test_distance(self):
        self.assertEqual(distance(["a", "b"], ["b", "a"]), 2)


if __name__ == "__main__":
    unittest.main()
