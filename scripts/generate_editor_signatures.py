import json
import re
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib.request import urlopen

import yaml


ROOT = Path(__file__).resolve().parents[1]
RAW = 'https://raw.githubusercontent.com/'
LUAU = RAW + 'luau-lang/luau/f46d879e28302a430029304f7f6a162aed66f103/'
TRACKER = RAW + 'MaximumADHD/Roblox-Client-Tracker/d39c04f3a8cab7f754c3bdb54e6c68dfd23f148e/'
DOCS = RAW + 'Roblox/creator-docs/a26aaab905a6594a9c788cceed5d4026def38071/content/en-us/reference/engine/'
DATATYPES = (
    'Axes', 'BrickColor', 'CatalogSearchParams', 'CFrame', 'Color3', 'ColorSequence',
    'ColorSequenceKeypoint', 'Content', 'DateTime', 'Faces', 'FloatCurveKey', 'Font',
    'Instance', 'NumberRange', 'NumberSequence', 'NumberSequenceKeypoint', 'OverlapParams',
    'PathWaypoint', 'PhysicalProperties', 'Random', 'Ray', 'RaycastParams', 'RaycastResult',
    'RBXScriptConnection', 'RBXScriptSignal', 'Rect', 'Region3', 'Region3int16',
    'SharedTable', 'TweenInfo', 'UDim', 'UDim2', 'Vector2', 'Vector2int16', 'Vector3',
    'Vector3int16',
)


def fetch(url):
    with urlopen(url, timeout=30) as response:
        return response.read().decode('utf-8')


def parameters_and_tail(signature):
    opening = signature.index('(')
    depth = 0
    for index in range(opening, len(signature)):
        if signature[index] == '(':
            depth += 1
        elif signature[index] == ')':
            depth -= 1
            if depth == 0:
                return signature[opening:index + 1], signature[index + 1:].strip()
    raise ValueError(signature)


def parameter_count(signature):
    params, _ = parameters_and_tail(signature)
    if params == '()':
        return 0
    depth, count = 0, 1
    for index, char in enumerate(params[1:-1], start=1):
        if char in '({[<':
            depth += 1
        elif char in ')}]' or (char == '>' and params[index - 1] != '-'):
            depth -= 1
        elif char == ',' and depth == 0:
            count += 1
    return count


def declarations(source):
    signatures = {}
    overloads = {}
    for name, declaration in re.findall(r'^\s*(?:@checked )?declare function (\w+)([^\n]+)', source, re.M):
        args, tail = parameters_and_tail(declaration)
        signatures.setdefault(name, f'{name}{args}: {tail.removeprefix(":").strip() or "()"}')
    for owner, fields in re.findall(r'^declare (\w+): \{\n(.*?)^\}', source, re.M | re.S):
        for name, declaration in re.findall(r'^    (\w+): (?:@checked )?([^\n]+),$', fields, re.M):
            key = f'{owner}.{name}'
            if declaration.startswith('(<') and ' & (' in declaration and declaration.endswith(')'):
                variants = []
                remaining = declaration
                while remaining.startswith('('):
                    wrapped, tail = parameters_and_tail(remaining)
                    args, result = parameters_and_tail(wrapped[1:-1])
                    if not result.startswith('->'):
                        break
                    variants.append(f'{key}{args}: {result[2:].strip()}')
                    if not tail:
                        signatures.setdefault(key, variants[0])
                        overloads.setdefault(key, variants)
                        break
                    remaining = tail.removeprefix('&').strip()
                continue
            if not re.match(r'^(?:<[^>]+>)?\(', declaration):
                continue
            args, tail = parameters_and_tail(declaration)
            if tail.startswith('->'):
                signatures.setdefault(key, f'{key}{args}: {tail[2:].strip()}')
    return signatures, overloads


def doc_type(name):
    return {'bool': 'boolean', 'int': 'number', 'int64': 'number', 'float': 'number',
            'double': 'number', 'Variant': 'any', 'Tuple': '...any'}.get(name, name)


def documented_calls(document, groups=('functions', 'constructors')):
    owner = document['name']
    for group in groups:
        for record in document.get(group, []):
            name = record['name']
            returns = [doc_type(value['type']) for value in record.get('returns', [])]
            args = []
            parameters = record.get('parameters', [])
            for param in parameters:
                annotation = doc_type(param['type'])
                if param.get('default') is not None and not annotation.endswith('?'):
                    annotation += '?'
                label = '...' if annotation.startswith('...') else param['name']
                if annotation == '...any' and len(parameters) == 1 and returns == ['()']:
                    annotation = '...T...'
                args.append(f'{label}: {annotation.removeprefix("...")}')
            result = owner if group == 'constructors' else '()'
            if len(returns) == 1:
                result = returns[0]
            elif returns:
                result = '(' + ', '.join(returns) + ')'
            yield name, f'{name}({", ".join(args)}): {result}'


def datatype_members(document):
    owner = document['name']
    constants = {record['name'] for record in document.get('constants', [])}
    members = {}
    for group in ('properties', 'constants'):
        for record in document.get(group, []):
            qualified = record['name']
            _, separator, name = qualified.partition('.')
            if separator and name and 'Deprecated' not in record.get('tags', []):
                kind = 'Value' if qualified in constants else 'Property'
                members[name] = (kind, doc_type(record['type']))
    for name, signature in documented_calls(document, ('methods',)):
        _, separator, member = name.partition(':')
        if separator and member:
            members.setdefault(member, ('Method', signature[len(owner) + 1:]))
    return members


def main():
    paths = ['globals/RobloxGlobals', 'globals/LuaGlobals']
    paths += [f'libraries/{name}' for name in ('bit32', 'buffer', 'coroutine', 'math', 'os', 'string', 'table', 'task', 'utf8')]
    paths += [f'datatypes/{name}' for name in DATATYPES]
    with ThreadPoolExecutor() as pool:
        sources = list(pool.map(fetch, [LUAU + 'Analysis/src/EmbeddedBuiltinDefinitions.cpp',
                                        TRACKER + 'LuauTypes.d.luau',
                                        *(DOCS + path + '.yaml' for path in paths)]))
    builtin_source, roblox_source, *documents = sources
    roblox_globals = re.search(r'-- SECTION BEGIN: RobloxGlobals\b(.*?)-- SECTION END: RobloxGlobals',
                               roblox_source, re.S).group(1)
    signatures = {}
    documented = {}
    datatypes = {}
    for source in documents:
        document = yaml.safe_load(source)
        for name, signature in documented_calls(document):
            variants = documented.setdefault(name, [])
            if signature not in variants:
                variants.append(signature)
        if document['name'] in DATATYPES:
            datatypes[document['name']] = datatype_members(document)
    signatures.update({name: variants[0] for name, variants in documented.items()})
    for source in (builtin_source, roblox_globals):
        typed, variants = declarations(source)
        signatures.update(typed)
        documented.update(variants)
    output = ROOT / 'src/Apps/ScriptViewer/Services/EditorBuiltinSignatures.lua'
    entries = '\n'.join(f'\t\t[{json.dumps(name)}] = {json.dumps(value, ensure_ascii=False)},'
                        for name, value in sorted(signatures.items()))
    overloads = '\n'.join(f'\t\t\t[{json.dumps(name)}] = table.freeze({{\n'
                          + ''.join(f'\t\t\t\t{{ {parameter_count(value)}, {json.dumps(value, ensure_ascii=False)} }},\n'
                                    for value in variants)
                          + '\t\t\t}),' for name, variants in sorted(documented.items()) if len(variants) > 1)
    datatype_entries = '\n'.join(
        f'\t\t\t{owner} = table.freeze({{\n'
        + ''.join(f'\t\t\t\t[{json.dumps(name)}] = {{ {json.dumps(kind)}, {json.dumps(detail)} }},\n'
                  for name, (kind, detail) in sorted(members.items()))
        + '\t\t\t}),' for owner, members in sorted(datatypes.items()) if members
    )
    output.write_text('--!strict\n\n-- Generated by scripts/generate_editor_signatures.py\n\n'
                      'local function Main()\n\treturn table.freeze({\n\t\tSignatures = table.freeze({\n'
                      + '\n'.join('\t' + line for line in entries.splitlines()) + '\n\t\t}),\n'
                      '\t\tOverloads = table.freeze({\n' + overloads + '\n\t\t}),\n'
                      '\t\tDatatypeMembers = table.freeze({\n' + datatype_entries + '\n\t\t}),\n\t})\nend\n\n'
                      'return { Main = Main }\n',
                      encoding='utf-8', newline='\n')


if __name__ == '__main__':
    main()
