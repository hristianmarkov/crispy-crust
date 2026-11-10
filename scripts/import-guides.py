#!/usr/bin/env python3
"""Import the supplied, authored DOCX guides without its editorial appendix.

Usage: python scripts/import-guides.py /path/to/Crispy_Crust_Starter_Guides_01-50.docx
Only Python's standard library is required. The generated JSON is committed so
the production build never needs access to the source document or this script.
"""
from __future__ import annotations

import json
import math
import re
import sys
import unicodedata
from pathlib import Path
from zipfile import ZipFile
import xml.etree.ElementTree as ET

W = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"
R = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}"
CATEGORIES = {
    "STARTER CARE": "Starter care",
    "FERMENTATION": "Fermentation",
    "TROUBLESHOOTING": "Troubleshooting",
    "SCHEDULING": "Scheduling",
    "RECIPES AND TECHNIQUES": "Recipes & techniques",
    "TOOLS AND BAKING MATH": "Tools & logging",
    "DISCARD": "Discard",
}
PUBLICATION_DATE = "2026-11-10"


def slugify(text: str) -> str:
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


def plain(el: ET.Element) -> str:
    return "".join(n.text or "" for n in el.iter(W + "t")).strip()


def style(el: ET.Element) -> str:
    s = el.find(W + "pPr/" + W + "pStyle")
    return s.get(W + "val", "") if s is not None else ""


def import_docx(source: Path) -> list[dict]:
    with ZipFile(source) as archive:
        root = ET.fromstring(archive.read("word/document.xml"))
        relationships = ET.fromstring(archive.read("word/_rels/document.xml.rels"))
    urls = {r.get("Id"): r.get("Target", "") for r in relationships}

    def markdown(el: ET.Element) -> str:
        parts = []
        for node in el:
            if node.tag == W + "hyperlink":
                text = plain(node)
                # DOCX citation labels already include brackets; Markdown supplies
                # its own pair so [3] remains a single, usable numbered link.
                if re.fullmatch(r"\[\d+\]", text):
                    text = text[1:-1]
                url = urls.get(node.get(R + "id"), "")
                if url.startswith("https://www.crispycrust.app"):
                    url = url.removeprefix("https://www.crispycrust.app") or "/"
                parts.append(f"[{text}]({url})" if url else text)
            elif node.tag == W + "r":
                parts.append("".join(n.text or "" for n in node.iter(W + "t")))
        return "".join(parts).strip()

    articles: dict[int, dict] = {}
    metadata: dict[int, dict] = {}
    active = None
    meta_active = None
    appendix = False
    in_sources = False
    for el in root.find(W + "body"):
        text = plain(el)
        paragraph_style = style(el)
        if el.tag == W + "p":
            if text.startswith("EDITORIAL APPENDIX"):
                appendix = True
                active = None
                continue
            if appendix:
                match = re.match(r"^(\d{2})\s{2,}(.+)", text)
                if paragraph_style == "Heading2" and match:
                    meta_active = int(match.group(1))
                    metadata.setdefault(meta_active, {})
                elif paragraph_style == "Metadata" and meta_active:
                    key, value = re.split(r"\s{2,}", text, maxsplit=1)
                    metadata[meta_active][key] = value
                continue
            match = re.fullmatch(r"JOURNAL (\d{2})\s*/\s*(.+)", text)
            if paragraph_style == "Kicker" and match:
                active = int(match.group(1))
                in_sources = False
                articles[active] = {
                    "number": active,
                    "category": CATEGORIES[match.group(2)],
                    "blocks": [],
                    "sources": [],
                }
                continue
            if not active or not text:
                continue
            article = articles[active]
            if paragraph_style == "Heading1":
                article["title"] = text
                continue
            if paragraph_style == "SourceLine" or text == "Sources" or text.startswith("Sources  "):
                in_sources = True
                for link in el.findall(".//" + W + "hyperlink"):
                    url = urls.get(link.get(R + "id"), "")
                    if url.startswith("https://"):
                        label = re.sub(r"^\d+\.\s*", "", plain(link))
                        article["sources"].append({"label": label, "url": url})
                continue
            if in_sources:
                continue
            if paragraph_style.startswith("Heading"):
                article["blocks"].append({"type": "heading", "text": text,
                    "id": slugify(text), "level": 3 if paragraph_style == "Heading3" else 2})
            elif paragraph_style in ("NumberStep", "ListBullet"):
                ordered = paragraph_style == "NumberStep"
                item = markdown(el)
                if ordered:
                    item = re.sub(r"^\d+\.\s+", "", item)
                blocks = article["blocks"]
                if blocks and blocks[-1]["type"] == "list" and blocks[-1]["ordered"] == ordered:
                    blocks[-1]["items"].append(item)
                else:
                    blocks.append({"type": "list", "ordered": ordered, "items": [item]})
            else:
                article["blocks"].append({"type": "paragraph", "text": markdown(el)})
        elif el.tag == W + "tbl" and active and not appendix and not in_sources:
            rows = []
            for row in el.findall(W + "tr"):
                cells = []
                for cell in row.findall(W + "tc"):
                    cells.append(" ".join(markdown(p) for p in cell.findall(W + "p") if plain(p)))
                rows.append(cells)
            if rows:
                articles[active]["blocks"].append({"type": "table", "headers": rows[0], "rows": rows[1:]})

    assert len(articles) == 50, f"Expected 50 articles, got {len(articles)}"
    assert len(metadata) == 50, f"Expected 50 metadata entries, got {len(metadata)}"
    for number, article in articles.items():
        meta = metadata[number]
        article["slug"] = meta["Proposed path"].removeprefix("/journal/")
        article["seoTitle"] = meta["SEO title"]
        article["description"] = meta["Meta description"]
        article["eyebrow"] = article["category"]
        article["publishedAt"] = PUBLICATION_DATE
        article["updatedAt"] = PUBLICATION_DATE
        article["intro"] = article["blocks"].pop(0)["text"]
        article["sections"] = []
        article["faqs"] = []

        # A final standalone question is a visible FAQ, not a duplicate body section.
        last_heading = next((i for i in range(len(article["blocks"]) - 1, -1, -1)
                             if article["blocks"][i]["type"] == "heading"), None)
        if last_heading is not None:
            tail = article["blocks"][last_heading:]
            if tail[0]["text"].endswith("?") and len(tail) == 2 and tail[1]["type"] == "paragraph":
                article["faqs"] = [{"question": tail[0]["text"], "answer": tail[1]["text"]}]
                del article["blocks"][last_heading:]

        readable_text = article["intro"] + " " + " ".join(
            block.get("text", "") + " " + " ".join(block.get("items", [])) + " "
            + " ".join(block.get("headers", [])) + " "
            + " ".join(" ".join(row) for row in block.get("rows", []))
            for block in article["blocks"]
        ) + " " + " ".join(faq["question"] + " " + faq["answer"] for faq in article["faqs"])
        words = len(re.findall(r"\S+", readable_text))
        article["readTime"] = f"{max(2, math.ceil(words / 220))} min read"
        article["relatedSlugs"] = []
        for target in meta.get("Internal link targets", "").split("  •  "):
            match = re.match(r"(\d{2})\s+", target)
            if match:
                article["relatedSlugs"].append(metadata[int(match.group(1))]["Proposed path"].removeprefix("/journal/"))
            elif target.startswith("/journal/"):
                article["relatedSlugs"].append(target.removeprefix("/journal/"))
            elif "Starter readiness" in target:
                article["relatedSlugs"].append("when-is-sourdough-starter-ready")
            elif "Bulk readiness" in target:
                article["relatedSlugs"].append("when-is-bulk-fermentation-done")
            elif "planning guide" in target.lower():
                article["relatedSlugs"].append("sourdough-baking-schedule")
        article["relatedSlugs"] = list(dict.fromkeys(article["relatedSlugs"]))[:4]
        article["targetQuery"] = meta["Target query"]

    # Contextual links turn the new library into connected resources.
    guide_links = {
        "feeding log": "sourdough-starter-feeding-log",
        "fridge guide": "sourdough-starter-in-fridge",
        "first-week method": "how-to-make-sourdough-starter",
        "starter readiness guide": "when-is-sourdough-starter-ready",
        "bulk readiness guide": "when-is-bulk-fermentation-done",
        "bake journal": "sourdough-bake-journal-template",
        "hydration guide": "calculate-sourdough-hydration-with-starter",
        "cold-proof guide": "cold-proof-sourdough-overnight",
        "small starter guide": "low-discard-sourdough-starter",
    }
    # Match a relevant phrase already present in the author's paragraph instead
    # of creating a repeated, disconnected list of links on every page.
    related_phrases = {
        "when-is-sourdough-starter-ready": ["ripe starter", "starter readiness", "reliable rise", "readiness criteria", "rises reliably", "ripeness cues"],
        "feed-sourdough-starter": ["feeding routine", "feeding method", "feed the starter"],
        "sourdough-starter-feeding-ratio": ["feeding ratio", "feed ratio", "1:1:1", "1:2:2"],
        "sourdough-starter-peak": ["peak window", "near its peak", "peak"],
        "sourdough-starter-not-rising": ["not rising", "new starter", "activity"],
        "sourdough-starter-in-fridge": ["fridge routine", "fridge maintenance", "refrigerated starter", "fridge"],
        "sourdough-starter-mold": ["signs of contamination", "pink or orange", "mould", "mold", "suspicious growth", "suspected contamination", "signs of spoilage"],
        "revive-sourdough-starter": ["neglected starter", "recovering", "revive"],
        "how-to-make-sourdough-starter": ["new starter", "young starter", "first-week"],
        "sourdough-starter-hooch": ["hooch", "surface liquid"],
        "sourdough-starter-feeding-log": ["feeding log", "log the feed", "record the feed"],
        "low-discard-sourdough-starter": ["small mother", "small starter", "small jar"],
        "levain-vs-starter": ["levain", "separate build"],
        "when-is-bulk-fermentation-done": ["bulk fermentation", "bulk readiness", "shaping decision", "bulk"],
        "bulk-fermentation-chart": ["rise target", "target rise", "bulk chart", "dough temperature"],
        "aliquot-jar-sourdough": ["aliquot jar", "dough sample", "sample jar"],
        "measure-sourdough-rise-percentage": ["percentage rise", "percentage-rise guide", "percent rise", "measured rise", "two readings"],
        "sourdough-dough-temperature": ["dough temperature", "temperature reading"],
        "sourdough-in-cold-kitchen": ["cool kitchen", "cold kitchen", "cooler dough"],
        "bulk-fermentation-vs-proofing": ["final proof", "proofing stage", "bulk fermentation"],
        "cold-proof-sourdough-overnight": ["cold proof", "overnight proof", "refrigerated proof"],
        "refrigerate-sourdough-during-bulk": ["chilled interruption", "refrigerating", "fridge"],
        "sourdough-poke-test": ["poke test"],
        "gummy-sourdough": ["gummy", "sticky crumb"],
        "dense-sourdough-bread": ["dense loaf", "dense crumb", "dense"],
        "underproofed-vs-overproofed-sourdough": ["underproofed", "overproofed", "proofing history"],
        "sourdough-dough-too-sticky": ["sticky dough", "sticking", "sticky"],
        "sourdough-spreads-after-shaping": ["spreading", "spreads", "spread"],
        "sourdough-baking-schedule": ["baking schedule", "schedule", "serving time"],
        "weekend-sourdough-baking-schedule": ["weekend", "Sunday", "Saturday"],
        "sourdough-schedule-running-late": ["running late", "bedtime", "late"],
        "beginner-sourdough-bread-recipe": ["first loaf", "white-flour sourdough", "bread recipe", "loaf"],
        "stretch-and-fold-sourdough": ["stretch and fold", "stretch-and-fold", "folds"],
        "shape-sourdough-boule": ["shaping", "surface tension", "boule"],
        "calculate-sourdough-hydration-with-starter": ["hydration", "starter hydration"],
        "bakers-percentages-sourdough": ["baker’s percentages", "baker’s percentage", "flour denominator", "percentages"],
        "sourdough-starter-tracker-app": ["starter tracker", "app", "reminders"],
        "sourdough-bake-journal-template": ["bake journal", "bake log", "bake record", "log"],
        "sourdough-no-oven-spring": ["oven spring"],
        "sourdough-crust-soft-after-cooling": ["soft crust", "crust", "cooling"],
        "what-is-sourdough-discard": ["discard", "unfed starter"],
        "store-sourdough-discard": ["stored discard", "storage", "fridge"],
        "sourdough-discard-pancakes": ["pancakes", "pancake"],
        "sourdough-discard-crackers": ["crackers", "cracker"],
        "sourdough-discard-recipes-by-amount": ["recipe amount", "grams available", "amount"],
        "sourdough-without-dutch-oven": ["Dutch oven", "covered bake", "steam"],
        "scale-sourdough-recipe": ["scale the recipe", "scaling", "dough weight", "scale"],
        "bake-two-sourdough-loaves-one-dutch-oven": ["two loaves", "second loaf"],
        "sourdough-focaccia-recipe": ["focaccia"],
    }
    for article in articles.values():
        linked = set()
        for block in article["blocks"]:
            if block["type"] != "paragraph":
                continue
            for phrase, slug in guide_links.items():
                if slug == article["slug"] or slug in linked:
                    continue
                pattern = re.compile(r"(?<!\[)\b" + re.escape(phrase) + r"\b(?!\])", re.IGNORECASE)
                if pattern.search(block["text"]):
                    block["text"] = pattern.sub(lambda m: f"[{m.group(0)}](/journal/{slug})", block["text"], count=1)
                    linked.add(slug)
        for slug in article["relatedSlugs"]:
            if len(linked) >= 2:
                break
            if slug in linked:
                continue
            for block in article["blocks"]:
                if block["type"] != "paragraph":
                    continue
                # Existing markdown links are kept whole; only plain spans change.
                spans = re.split(r"(\[[^\]]+\]\([^\)]+\))", block["text"])
                matched = False
                for i in range(0, len(spans), 2):
                    for phrase in related_phrases.get(slug, []):
                        pattern = re.compile(r"\b" + re.escape(phrase) + r"\b", re.IGNORECASE)
                        if pattern.search(spans[i]):
                            spans[i] = pattern.sub(lambda m: f"[{m.group(0)}](/journal/{slug})", spans[i], count=1)
                            matched = True
                            break
                    if matched:
                        break
                if matched:
                    block["text"] = "".join(spans)
                    linked.add(slug)
                    break
        tool = None
        if article["number"] in (1, 2, 5, 9, 11, 12):
            tool = ("Use the starter feeding calculator", "/tools/starter-feeding-calculator", "to calculate the build you need while keeping a reserve.")
        elif article["number"] in (13, 14, 16):
            tool = ("Use the dough rise calculator", "/tools/sourdough-rise-calculator", "to convert your own starting measurement and recipe target into a mark.")
        elif article["number"] in (18, 24, 25, 27, 28, 29, 31, 49):
            tool = ("Try the sourdough schedule calculator", "/tools/sourdough-schedule-calculator", "with your recipe’s stage durations, then adjust the plan to what your dough shows.")
        elif article["number"] in (26, 33, 36, 37, 48, 50):
            tool = ("Check the sourdough hydration calculator", "/tools/sourdough-hydration-calculator", "to include the flour and water in your starter without counting them twice.")
        elif article["number"] in (42, 43, 44, 45, 46):
            tool = ("Find a discard recipe by grams available", "/tools/discard-recipe-finder", "and compare the original recipes before choosing what to make.")
        if tool:
            article["blocks"].append({"type": "paragraph", "text": f"[{tool[0]}]({tool[1]}) {tool[2]}"})

    downloads = {
        9: ("Starter feeding log", "starter-feeding-log"),
        13: ("Bulk fermentation chart", "bulk-fermentation-chart"),
        27: ("Weekend sourdough schedule", "weekend-sourdough-schedule"),
        37: ("Sourdough formula card", "sourdough-formula-card"),
        39: ("Sourdough bake journal", "sourdough-bake-journal"),
    }
    for number, (label, filename) in downloads.items():
        articles[number]["downloads"] = [
            {"label": f"{label} — A4 PDF", "url": f"/downloads/{filename}-a4.pdf"},
            {"label": f"{label} — US Letter PDF", "url": f"/downloads/{filename}-letter.pdf"},
            {"label": f"{label} — printable HTML", "url": f"/downloads/{filename}.html"},
        ]
    result = list(articles.values())
    all_slugs = {a["slug"] for a in result} | {"sourdough-baking-schedule", "when-is-sourdough-starter-ready", "when-is-bulk-fermentation-done"}
    assert len(all_slugs) == 53
    for article in result:
        assert article["sources"], f"Missing sources: {article['number']}"
        assert all(s in all_slugs for s in article["relatedSlugs"]), article["relatedSlugs"]
        assert all(len(row) == len(block["headers"]) for block in article["blocks"] if block["type"] == "table" for row in block["rows"])
    return result


if __name__ == "__main__":
    source = Path(sys.argv[1])
    destination = Path(__file__).resolve().parents[1] / "src/data/imported-guides.json"
    articles = import_docx(source)
    destination.write_text(json.dumps(articles, ensure_ascii=False, indent=2) + "\n")
    print(f"Imported {len(articles)} guides, {sum(len(a['blocks']) for a in articles)} content blocks, "
          f"{sum(len(a['sources']) for a in articles)} linked sources to {destination}")
