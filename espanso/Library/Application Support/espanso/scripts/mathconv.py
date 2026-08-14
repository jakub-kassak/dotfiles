#!/usr/bin/env python3
"""Convert text to Unicode subscript/superscript glyphs.

Usage: mathconv.py sub|sup  <text>
Characters without a Unicode sub/superscript glyph are left unchanged.
"""
import sys

# Subscript: only a partial set of letters exists in Unicode.
SUB = str.maketrans(
    "aehijklmnoprstuvx0123456789+-=()",
    "ₐₑₕᵢⱼₖₗₘₙₒₚᵣₛₜᵤᵥₓ₀₁₂₃₄₅₆₇₈₉₊₋₌₍₎",
)

# Superscript: all 26 lowercase; uppercase minus C F Q S X Y Z.
SUP = str.maketrans({
    # note: no superscript 'q' exists in Unicode, so it's excluded
    **dict(zip("abcdefghijklmnoprstuvwxyz",
               "ᵃᵇᶜᵈᵉᶠᵍʰⁱʲᵏˡᵐⁿᵒᵖʳˢᵗᵘᵛʷˣʸᶻ")),
    **dict(zip("ABDEGHIJKLMNOPRTUVW",
               "ᴬᴮᴰᴱᴳᴴᴵᴶᴷᴸᴹᴺᴼᴾᴿᵀᵁⱽᵂ")),
    **dict(zip("0123456789", "⁰¹²³⁴⁵⁶⁷⁸⁹")),
    **dict(zip("+-=()", "⁺⁻⁼⁽⁾")),
})

mode = sys.argv[1] if len(sys.argv) > 1 else "sub"
text = sys.argv[2] if len(sys.argv) > 2 else ""
sys.stdout.write(text.translate(SUB if mode == "sub" else SUP))
