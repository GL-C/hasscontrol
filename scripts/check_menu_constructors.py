"""Check Garmin menu call arity, which builds with type checking off miss."""
from pathlib import Path
import re
import sys

TOKENS = re.compile(r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|[A-Za-z_]\w*|\S', re.S)


def check(source):
    tokens = [m.group() for m in TOKENS.finditer(source)
              if not m.group().startswith(('//', '/*'))]
    errors = []
    checked = 0
    for i in range(len(tokens) - 4):
        if tokens[i:i + 3] != ['new', 'Ui', '.']:
            continue
        expected = {'MenuItem': 4, 'Menu2': 1}.get(tokens[i + 3])
        if expected is None or tokens[i + 4] != '(':
            continue
        depth = 0
        count = 1
        for token in tokens[i + 5:]:
            if token == ')' and depth == 0:
                break
            if token in ('(', '[', '{'):
                depth += 1
            elif token in (')', ']', '}'):
                depth -= 1
            elif token == ',' and depth == 0:
                count += 1
        checked += 1
        if count != expected:
            errors.append(f'{tokens[i + 3]} expects {expected} arguments, got {count}')
    return checked, errors


if __name__ == '__main__':
    paths = [Path(p) for p in sys.argv[1:]] or list(Path('widget/source').rglob('*.mc'))
    checked = 0
    errors = []
    for path in paths:
        n, failures = check(path.read_text())
        checked += n
        errors.extend(f'{path}: {failure}' for failure in failures)
    if errors:
        sys.exit('\n'.join(errors))
    print(f'Checked {checked} Garmin menu constructors.')
