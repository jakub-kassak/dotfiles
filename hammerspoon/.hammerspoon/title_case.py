import re, sys
minor = set('a an and as at but by en for if in nor of on or per the to v via vs'.split())
def convert(line):
    matches = list(re.finditer(r"[^\W\d_]+(?:['’][^\W\d_]+)*", line, re.UNICODE))
    def replace(m):
        word = m.group().lower()
        first, last = matches[0].start(), matches[-1].start()
        after_colon = bool(re.search(r':\s*$', line[:m.start()]))
        return word if word in minor and m.start() not in (first, last) and not after_colon else word[0].upper() + word[1:]
    return re.sub(r"[^\W\d_]+(?:['’][^\W\d_]+)*", replace, line, flags=re.UNICODE)
sys.stdout.write(''.join(convert(line) for line in sys.stdin.readlines()))
