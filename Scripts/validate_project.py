#!/usr/bin/env python3
"""Dependency-free structural checks. Does NOT compile or type-check Swift."""
import pathlib
import plistlib
import re
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[1]

def require(condition, message):
    if not condition:
        raise AssertionError(message)

class OpenStepParser:
    def __init__(self, text):
        self.tokens = re.findall(r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|[{}()=;,]|[^\s{}()=;,]+', text, re.S)
        self.tokens = [t for t in self.tokens if not t.startswith(('//', '/*'))]
        self.position = 0
    def take(self, expected=None):
        value = self.tokens[self.position]
        self.position += 1
        require(expected is None or value == expected, f'Expected {expected}, got {value}')
        return value
    def value(self):
        token = self.take()
        if token == '{':
            result = {}
            while self.tokens[self.position] != '}':
                key = self.take().strip('"')
                require(key not in result, f'Duplicate key: {key}')
                self.take('='); result[key] = self.value(); self.take(';')
            self.take('}'); return result
        if token == '(':
            result = []
            while self.tokens[self.position] != ')':
                result.append(self.value())
                if self.tokens[self.position] != ')': self.take(',')
            self.take(')'); return result
        return token[1:-1] if token.startswith('"') else token

parser = OpenStepParser((ROOT / 'GlassType.xcodeproj/project.pbxproj').read_text())
project = parser.value()
require(parser.position == len(parser.tokens), 'Unexpected trailing project content')
objects = project['objects']
require(project['rootObject'] in objects, 'Missing root object')

def validate_references(value):
    if isinstance(value, dict):
        for child in value.values(): validate_references(child)
    elif isinstance(value, list):
        for child in value: validate_references(child)
    elif re.fullmatch('[0-9A-F]{24}', value):
        require(value in objects, f'Dangling reference: {value}')
validate_references(objects)
for value in objects.values():
    if value['isa'] == 'PBXFileReference' and value.get('sourceTree') == '<group>':
        require((ROOT / value['path']).is_file(), f'Missing file: {value["path"]}')

targets = {o['name']: o for o in objects.values() if o['isa'] == 'PBXNativeTarget'}
require(set(targets) == {'GlassType', 'GlassTypeKeyboard'}, 'Expected app and keyboard targets')
for name, target in targets.items():
    phases = [objects[ref] for ref in target['buildPhases']]
    source_phase = next(p for p in phases if p['isa'] == 'PBXSourcesBuildPhase')
    actual_sources = {objects[objects[ref]['fileRef']]['path'] for ref in source_phase['files']}
    prefix = 'App' if name == 'GlassType' else 'Keyboard'
    expected_sources = {str(p.relative_to(ROOT)) for folder in [prefix, 'Shared'] for p in (ROOT / folder).glob('*.swift')}
    require(actual_sources == expected_sources, f'{name}: sources not fully included')
    products = [objects[ref] for ref in target['packageProductDependencies']]
    require(any(p['productName'] == 'KeyboardCore' for p in products), f'{name}: missing package')
    resource_phase = next(p for p in phases if p['isa'] == 'PBXResourcesBuildPhase')
    require(any(objects[objects[ref]['fileRef']]['path'].endswith('PrivacyInfo.xcprivacy') for ref in resource_phase['files']), f'{name}: privacy manifest not bundled')

app = targets['GlassType']
embed = next(objects[ref] for ref in app['buildPhases'] if objects[ref]['isa'] == 'PBXCopyFilesBuildPhase')
require(embed['dstSubfolderSpec'] == '13', 'Extension must be embedded into PlugIns')
require(objects[objects[embed['files'][0]]['fileRef']]['path'] == 'GlassTypeKeyboard.appex', 'Wrong embedded product')
require(bool(app['dependencies']), 'Missing extension build dependency')

plists = {}
for path in [*ROOT.glob('*/Info.plist'), *ROOT.glob('*/*.entitlements'), *ROOT.glob('*/PrivacyInfo.xcprivacy')]:
    plists[str(path.relative_to(ROOT))] = plistlib.loads(path.read_bytes())
keyboard = plists['Keyboard/Info.plist']['NSExtension']
require(keyboard['NSExtensionPointIdentifier'] == 'com.apple.keyboard-service', 'Incorrect extension point')
require(keyboard['NSExtensionPrincipalClass'] == '$(PRODUCT_MODULE_NAME).KeyboardViewController', 'Incorrect principal class')
group = plists['App/App.entitlements']['com.apple.security.application-groups']
require(group == plists['Keyboard/Keyboard.entitlements']['com.apple.security.application-groups'], 'App Group mismatch')
require(group[0] in (ROOT / 'Shared/Settings.swift').read_text(), 'Settings App Group mismatch')
for name in ['App', 'Keyboard']:
    require(not plists[f'{name}/PrivacyInfo.xcprivacy']['NSPrivacyTracking'], 'Tracking must be disabled')

scheme = ET.parse(ROOT / 'GlassType.xcodeproj/xcshareddata/xcschemes/GlassType.xcscheme')
for ref in scheme.findall('.//BuildableReference'):
    require(ref.attrib['BlueprintIdentifier'] in objects, 'Scheme target missing')
require((ROOT / 'Core/Package.swift').is_file(), 'Missing local Swift Package')
require(len(list((ROOT / 'Core/Tests').rglob('*.swift'))) > 0, 'Missing XCTest sources')
for path in [*ROOT.glob('App/*.swift'), *ROOT.glob('Keyboard/*.swift'), *ROOT.glob('Shared/*.swift'), *ROOT.glob('Core/Sources/**/*.swift')]:
    require(not re.search(r'\b(URLSession|NSURLConnection|NWConnection|WKWebView)\b|https?://', path.read_text()), f'Unexpected network API: {path}')
import hashlib
import json
resources = ROOT / 'Core/Sources/KeyboardCore/Resources'
manifest = json.loads((resources / 'lexicon-manifest.json').read_text())
for language in ['en', 'ru', 'uk']:
    data = (resources / f'lexicon_{language}.txt').read_bytes()
    words = data.decode().splitlines()
    require(len(words) == manifest['languages'][language]['words'], f'{language}: wrong word count')
    require(len(words) >= 25000 and len(words) == len(set(words)), f'{language}: missing or duplicate words')
    require(hashlib.sha256(data).hexdigest() == manifest['languages'][language]['sha256'], f'{language}: corpus changed')
for name in ['Dictionary-Attribution.txt', 'CC-BY-SA-4.0.txt', 'MPL-1.1.txt']:
    require((resources / name).is_file(), f'Missing license {name}')
print(f'PASS: parsed Xcode project; {len(objects)} objects; 2 targets; source membership, local package, embed phase, plists, entitlements, privacy manifests and scheme references.')
print('LIMIT: structural checks only. Swift tests, type checking, Xcode build, signing and device behavior have NOT been verified.')
