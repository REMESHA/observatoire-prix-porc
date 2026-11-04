"""Téléchargement de secours, appelé par 01_extract.R quand curl échoue.

Le serveur de la Commission européenne ferme parfois la connexion sécurisée
sans le signal de fin attendu (« unexpected eof while reading »). OpenSSL 3,
utilisé par curl et donc par R, traite ce cas comme une erreur. Python permet
de le tolérer (option OP_IGNORE_UNEXPECTED_EOF). La réponse est ensuite
validée comme JSON complet : une réponse tronquée est rejetée.

Usage : python3 telecharger.py <url> <fichier_sortie> <délai_en_secondes>
"""
import json
import ssl
import sys
import urllib.request


def main() -> int:
    url, sortie, delai = sys.argv[1], sys.argv[2], float(sys.argv[3])
    ctx = ssl.create_default_context()
    ctx.options |= getattr(ssl, "OP_IGNORE_UNEXPECTED_EOF", 0)
    req = urllib.request.Request(url, headers={
        "Accept": "application/json",
        "User-Agent": "observatoire-prix-porc (projet portfolio)",
    })
    with urllib.request.urlopen(req, context=ctx, timeout=delai) as resp:
        if resp.status != 200:
            print(f"statut HTTP {resp.status}", file=sys.stderr)
            return 1
        corps = resp.read()
    json.loads(corps)  # lève une erreur si la réponse est incomplète
    with open(sortie, "wb") as f:
        f.write(corps)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:  # message court, lu par R
        print(f"{type(e).__name__}: {e}", file=sys.stderr)
        sys.exit(1)
