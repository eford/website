#!/usr/bin/env python3
"""
parse_publications.py

Reads a BibTeX file exported from NASA ADS, fetches abstracts via the ADS API,
and writes one TOML file per publication to _data/publications/YEAR/.

Config file:.ads_config (in the same directory as this script, or site root)
Format:
    ADS_API_KEY = your_key_here

Usage:
    python parse_publications.py references.bib
    python parse_publications.py references.bib --config /path/to/.ads_config
    python parse_publications.py references.bib --dry-run
"""

import argparse
import os
import re
import sys
import time
from collections import defaultdict
from pathlib import Path

import requests

# ---------------------------------------------------------------------------
# Optional: bibtexparser is the cleanest approach; fall back to regex if absent
# ---------------------------------------------------------------------------
try:
    import bibtexparser
    from bibtexparser.bparser import BibTexParser
    from bibtexparser.customization import convert_to_unicode
    HAS_BIBTEXPARSER = True
except ImportError:
    HAS_BIBTEXPARSER = False
    print("Warning: bibtexparser not found. Install with: pip install bibtexparser")
    print("Falling back to basic regex parser.\n")

# ---------------------------------------------------------------------------
# ADS journal macro expansion
# ---------------------------------------------------------------------------
ADS_MACROS = {
    r"\apj":       "ApJ",
    r"\apjl":      "ApJL",
    r"\apjs":      "ApJS",
    r"\aj":        "AJ",
    r"\aap":       "A&A",
    r"\aapr":      "A&A Rev.",
    r"\aaps":      "A&AS",
    r"\mnras":     "MNRAS",
    r"\pasp":      "PASP",
    r"\pasa":      "PASA",
    r"\pasj":      "PASJ",
    r"\nat":       "Nature",
    r"\natast":    "Nature Astronomy",
    r"\sci":       "Science",
    r"\icarus":    "Icarus",
    r"\araa":      "ARA&A",
    r"\ssr":       "Space Sci. Rev.",
    r"\solphys":   "Sol. Phys.",
    r"\memsai":    "Mem. Soc. Astron. Italiana",
    r"\physrep":   "Phys. Rep.",
    r"\prd":       "Phys. Rev. D",
    r"\prl":       "Phys. Rev. Lett.",
    r"\pre":       "Phys. Rev. E",
    r"\jgr":       "J. Geophys. Res.",
    r"\aplett":    "Astrophys. Lett.",
    r"\asr":       "Adv. Space Res.",
}

# ---------------------------------------------------------------------------
# LaTeX → Unicode conversion for common expressions
# ---------------------------------------------------------------------------
LATEX_UNICODE = {
    r"\alpha":      "α",  r"\beta":       "β",  r"\gamma":      "γ",
    r"\delta":      "δ",  r"\epsilon":    "ε",  r"\zeta":       "ζ",
    r"\eta":        "η",  r"\theta":      "θ",  r"\iota":       "ι",
    r"\kappa":      "κ",  r"\lambda":     "λ",  r"\mu":         "μ",
    r"\nu":         "ν",  r"\xi":         "ξ",  r"\pi":         "π",
    r"\rho":        "ρ",  r"\sigma":      "σ",  r"\tau":        "τ",
    r"\upsilon":    "υ",  r"\phi":        "φ",  r"\chi":        "χ",
    r"\psi":        "ψ",  r"\omega":      "ω",
    r"\Gamma":      "Γ",  r"\Delta":      "Δ",  r"\Theta":      "Θ",
    r"\Lambda":     "Λ",  r"\Xi":         "Ξ",  r"\Pi":         "Π",
    r"\Sigma":      "Σ",  r"\Upsilon":    "Υ",  r"\Phi":        "Φ",
    r"\Psi":        "Ψ",  r"\Omega":      "Ω",
    r"\sim":        "~",  r"\approx":     "≈",  r"\leq":        "≤",
    r"\geq":        "≥",  r"\neq":        "≠",  r"\pm":         "±",
    r"\times":      "×",  r"\cdot":       "·",  r"\infty":      "∞",
    r"\odot":       "⊙",  r"\oplus":      "⊕",  r"\circ":       "°",
    r"\AA":         "Å",  r"\deg":        "°",
    r"\,":          " ",  r"\ ":          " ",  r"\;":          " ",
    r"~":           " ",
}

# ---------------------------------------------------------------------------
# Config loader
# ---------------------------------------------------------------------------

def load_config(config_path: str) -> dict:
    config = {}
    path = Path(config_path)
    if not path.exists():
        print(f"Error: config file not found at {config_path}")
        sys.exit(1)
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" in line:
                key, _, val = line.partition("=")
                config[key.strip()] = val.strip()
    return config

# ---------------------------------------------------------------------------
# LaTeX cleanup
# ---------------------------------------------------------------------------

def expand_macros(text: str) -> str:
    """Expand ADS journal macros."""
    for macro, expansion in ADS_MACROS.items():
        # Match macro not followed by a letter (avoid partial matches)
        text = re.sub(re.escape(macro) + r"(?![a-zA-Z])", expansion, text)
    return text

def latex_to_unicode(text: str) -> str:
    """
    Convert simple LaTeX math expressions to Unicode.
    Handles:
      - Subscripts/superscripts with single chars: M_\odot -> M⊙, x^2 -> x²
      - Greek letters and common symbols
      - Removes surrounding $ delimiters when expression is simple
    """
    superscript_map = str.maketrans("0123456789+-n", "⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻ⁿ")
    subscript_map   = str.maketrans("0123456789", "₀₁₂₃₄₅₆₇₈₉")

    # Replace known symbols first
    for latex, uni in LATEX_UNICODE.items():
        text = text.replace(latex, uni)

    # Superscripts: ^{x} or ^x (single char)
    text = re.sub(r"\^\{([0-9+\-n])\}", lambda m: m.group(1).translate(superscript_map), text)
    text = re.sub(r"\^([0-9+\-n])",     lambda m: m.group(1).translate(superscript_map), text)

    # Subscripts: _{x} or _x (single digit)
    text = re.sub(r"_\{([0-9])\}", lambda m: m.group(1).translate(subscript_map), text)
    text = re.sub(r"_([0-9])",     lambda m: m.group(1).translate(subscript_map), text)

    # Remove braces used purely for grouping: {M} -> M
    text = re.sub(r"\{([^{}]+)\}", r"\1", text)

    # Remove $ delimiters around what are now plain-text expressions
    # Only strip if no backslash remains inside (i.e., complex LaTeX left alone)
    def strip_dollars(m):
        inner = m.group(1)
        return inner if "\\" not in inner else m.group(0)
    text = re.sub(r"\$([^$]+)\$", strip_dollars, text)

    return text.strip()

def clean_bibtex_value(text: str) -> str:
    """Remove outer braces, expand macros, convert LaTeX."""
    text = text.strip().strip("{}")
    text = expand_macros(text)
    text = latex_to_unicode(text)
    return text

# ---------------------------------------------------------------------------
# BibTeX parsing
# ---------------------------------------------------------------------------

def parse_bibtex_regex(bib_text: str) -> list[dict]:
    """Minimal fallback BibTeX parser using regex."""
    entries = []
    # Match each @TYPE{key,... }
    entry_pattern = re.compile(
        r"@(\w+)\s*\{\s*([^,]+),\s*(.*?)\n\}", re.DOTALL
    )
    field_pattern = re.compile(
        r"(\w+)\s*=\s*(\{(?:[^{}]|\{[^{}]*\})*\}|\"[^\"]*\"|[\w\\]+)\s*,?",
        re.DOTALL
    )
    for m in entry_pattern.finditer(bib_text):
        entry = {
            "ENTRYTYPE": m.group(1).lower(),
            "ID":        m.group(2).strip(),
        }
        for fm in field_pattern.finditer(m.group(3)):
            key = fm.group(1).lower()
            val = fm.group(2).strip().strip('"{').rstrip('}"')
            entry[key] = val
        entries.append(entry)
    return entries

def parse_bibtex_file(bib_path: str) -> list[dict]:
    with open(bib_path, encoding="utf-8") as f:
        bib_text = f.read()

    if HAS_BIBTEXPARSER:
        parser = BibTexParser(common_strings=True)
        parser.customization = convert_to_unicode
        db = bibtexparser.loads(bib_text, parser=parser)
        return db.entries
    else:
        return parse_bibtex_regex(bib_text)

# ---------------------------------------------------------------------------
# ADS abstract fetching
# ---------------------------------------------------------------------------

def fetch_abstract(bibcode: str, api_key: str) -> str:
    """Fetch abstract from ADS API using the bibcode."""
    # Extract bibcode from adsurl if a full URL was passed
    bibcode = bibcode.rstrip("/").split("/")[-1]
    url = f"https://api.adsabs.harvard.edu/v1/search/query"
    headers = {"Authorization": f"Bearer {api_key}"}
    params  = {
        "q":  f"bibcode:{bibcode}",
        "fl": "abstract",
        "rows": 1,
    }
    try:
        resp = requests.get(url, headers=headers, params=params, timeout=15)
        resp.raise_for_status()
        docs = resp.json().get("response", {}).get("docs", [])
        if docs and "abstract" in docs[0]:
            abstract = docs[0]["abstract"]
            abstract = expand_macros(abstract)
            abstract = latex_to_unicode(abstract)
            return abstract
    except Exception as e:
        print(f"    Warning: could not fetch abstract for {bibcode}: {e}")
    return ""

# ---------------------------------------------------------------------------
# TOML serialization (no external dependency)
# ---------------------------------------------------------------------------

def toml_multiline_string(text: str) -> str:
    """Encode a string as a TOML multiline literal if it contains newlines,
    otherwise as a regular quoted string."""
    if not text:
        return '""'
    # Escape backslashes and double-quotes for basic strings
    # For multiline, use '''... ''' style (literal) to avoid escaping
    if "\n" in text:
        # Ensure no ''' appears in the text itself
        text = text.replace("'''", "'''")
        return f"'''\n{text}\n'''"
    else:
        text = text.replace("\\", "\\\\").replace('"', '\\"')
        return f'"{text}"'

def toml_string(text: str) -> str:
    if not text:
        return '""'
    text = text.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{text}"'

def write_toml(path: Path, entry: dict, abstract: str):
    """Write a publication TOML file."""

    def field(key, val):
        return f'{key:<16} = {toml_string(str(val))}\n'

    lines = []
    lines.append(f'# {entry.get("title_clean", entry.get("title",""))}\n\n')

    # Core bibliographic fields
    for key in ["title", "author", "year", "journal", "volume", "pages",
                "month", "eid"]:
        val = entry.get(key, "")
        if val:
            lines.append(field(key, clean_bibtex_value(val)))

    # Identifiers
    for key in ["doi", "adsurl", "bibcode", "eprint", "archiveprefix",
                "primaryclass", "adsnote"]:
        val = entry.get(key, "")
        if val:
            lines.append(field(key, val.strip("{}")))

    # Entry type
    lines.append(field("entrytype", entry.get("ENTRYTYPE", "article")))

    # Abstract (multiline)
    lines.append(f'\nabstract         = {toml_multiline_string(abstract)}\n')

    # Placeholder arrays
    lines.append('\ntags             = [""]\n')
    lines.append('research_themes  = [""]\n')

    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.writelines(lines)

# ---------------------------------------------------------------------------
# Filename generation
# ---------------------------------------------------------------------------

def first_author_last_name(author_field: str) -> str:
    """Extract the last name of the first author from an ADS author string."""
    # ADS format: "Last, First and Last, First and..."
    first = author_field.split(" and ")[0].strip().strip("{}")
    last  = first.split(",")[0].strip()
    # Sanitize for use in a filename
    last  = re.sub(r"[^a-zA-Z0-9_-]", "", last)
    return last or "unknown"

def generate_filename(entry: dict, used: dict) -> str:
    """
    Generate a filename of the form LastName_YEARx.toml where x is a letter
    suffix (omitted if no conflict, then a, b, c,... for conflicts).
    `used` is a dict mapping (lastname, year) -> count, mutated in place.
    """
    last = first_author_last_name(entry.get("author", "unknown"))
    year = clean_bibtex_value(entry.get("year", "0000"))
    key  = (last, year)
    used[key] = used.get(key, 0) + 1
    count = used[key]
    suffix = "" if count == 1 else chr(ord("a") + count - 2)
    return f"{last}_{year}{suffix}.toml"

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Convert ADS BibTeX to TOML publication files.")
    parser.add_argument("bibfile",           help="Path to the.bib file")
    parser.add_argument("--config",          default=".ads_config",
                        help="Path to config file containing ADS_API_KEY (default:.ads_config)")
    parser.add_argument("--outdir",          default="_data/publications",
                        help="Root output directory (default: _data/publications)")
    parser.add_argument("--dry-run",         action="store_true",
                        help="Parse and print filenames without writing files or calling ADS")
    parser.add_argument("--delay",           type=float, default=0.5,
                        help="Seconds to wait between ADS API calls (default: 0.5)")
    args = parser.parse_args()

    config  = load_config(args.config)
    api_key = config.get("ADS_API_KEY", "")
    #if not api_key and not args.dry_run:
    #    print("Error: ADS_API_KEY not found in config file.")
    #    sys.exit(1)

    print(f"Parsing {args.bibfile}...")
    entries = parse_bibtex_file(args.bibfile)
    print(f"Found {len(entries)} entries.\n")

    # Two-pass filename generation: first collect all (last, year) pairs so
    # we can assign suffixes correctly even if entries aren't sorted by year.
    # Count occurrences first.
    key_counts: dict = defaultdict(int)
    for e in entries:
        last = first_author_last_name(e.get("author", "unknown"))
        year = clean_bibtex_value(e.get("year", "0000"))
        key_counts[(last, year)] += 1

    # Build suffix iterators for conflicting keys
    suffix_iters = {
        k: iter("abcdefghijklmnopqrstuvwxyz")
        for k, count in key_counts.items() if count > 1
    }
    seen: dict = defaultdict(int)

    for entry in entries:
        last = first_author_last_name(entry.get("author", "unknown"))
        year = clean_bibtex_value(entry.get("year", "0000"))
        key  = (last, year)
        seen[key] += 1

        if key_counts[key] == 1:
            suffix = ""
        else:
            # Assign a, b, c,... in order of appearance
            suffix = chr(ord("a") + seen[key] - 1)

        filename = f"{last}_{year}{suffix}.toml"
        out_path = Path(args.outdir) / year / filename

        title = clean_bibtex_value(entry.get("title", "(no title)"))
        print(f"  {filename}")
        print(f"    Title:  {title[:72]}{'...' if len(title) > 72 else ''}")

        if args.dry_run:
            print(f"    [dry-run] would write to {out_path}\n")
            continue

        # Fetch abstract
        adsurl  = entry.get("adsurl", "")
        bibcode = entry.get("bibcode", adsurl.rstrip("/").split("/")[-1] if adsurl else "")
        abstract = ""
        if len(api_key) >0:
            if bibcode:
                print(f"    Fetching abstract for {bibcode}...")
                abstract = fetch_abstract(bibcode, api_key)
                time.sleep(args.delay)   # be polite to the ADS API
            else:
                print(f"    Warning: no bibcode or adsurl found, skipping abstract.")

        write_toml(out_path, entry, abstract)
        print(f"    Written: {out_path}\n")

    print("Done!")

if __name__ == "__main__":
    main()
