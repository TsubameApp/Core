#!/usr/bin/env node

/*
 * Copyright (C) 2026 Tsubame Authors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import {createHash} from 'node:crypto';
import {mkdtemp, mkdir, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';

const upstreamCommit = '77e200428902abf4fa48284df92da7af3dcb4162';
const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const coreRoot = path.resolve(scriptDirectory, '../..');
const thirdPartyRoot = path.join(coreRoot, 'ThirdParty/Yomitan');

const sources = {
    japaneseTransforms: {
        path: 'ext/js/language/ja/japanese-transforms.js',
        sha256: '9e928202a2f8f8ed1a17961b3cd93b56cddaf9cdda98b8625dc689f8acdaf2a1',
    },
    languageTransforms: {
        path: 'ext/js/language/language-transforms.js',
        sha256: 'e454f0a7333170aa1e96e42e546a316aee9c31b8b1d8056d45c034e1470c8a14',
    },
    languageTransformer: {
        path: 'ext/js/language/language-transformer.js',
        sha256: 'f45db85ae6c5628b65ef0c45d48a47f6091f43109d723f81826dc4a1ce3ae198',
    },
    japaneseTests: {
        path: 'test/language/japanese-transforms.test.js',
        sha256: '30dc282e0e3b3fb33c09a995d529b575d6aa84aebc9bf30b566a0c0dfd5e8454',
    },
};

for (const source of Object.values(sources)) {
    const data = await readFile(path.join(thirdPartyRoot, source.path));
    const actual = createHash('sha256').update(data).digest('hex');
    if (actual !== source.sha256) {
        throw new Error(`Unexpected SHA-256 for ${source.path}: ${actual}`);
    }
}

const temporaryDirectory = await mkdtemp(path.join(tmpdir(), 'tsubame-yomitan-export-'));
try {
    const descriptor = await loadDescriptor(temporaryDirectory);
    const ruleFile = flattenDescriptor(descriptor);
    if (ruleFile.conditions.length !== 22 || ruleFile.transforms.length !== 55) {
        throw new Error(
            `Unexpected descriptor shape: ${ruleFile.conditions.length} conditions, ` +
            `${ruleFile.transforms.length} transforms`,
        );
    }

    const fixtureFile = await loadFixtures(temporaryDirectory);
    const resourceDirectory = path.join(coreRoot, 'Sources/TsubameCore/Resources');
    const testResourceDirectory = path.join(coreRoot, 'Tests/TsubameCoreTests/Resources');
    await mkdir(resourceDirectory, {recursive: true});
    await mkdir(testResourceDirectory, {recursive: true});
    await writeCanonicalJSON(
        path.join(resourceDirectory, 'JapaneseDeinflectionRules.json'),
        ruleFile,
    );
    await writeCanonicalJSON(
        path.join(testResourceDirectory, 'YomitanJapaneseDeinflectionFixtures.json'),
        fixtureFile,
    );
} finally {
    await rm(temporaryDirectory, {recursive: true, force: true});
}

async function loadDescriptor(temporaryDirectory) {
    const sourcePath = path.join(thirdPartyRoot, sources.japaneseTransforms.path);
    let source = await readFile(sourcePath, 'utf8');
    const importStatement =
        "import {suffixInflection, wholeWordInflection} from '../language-transforms.js';";
    if (!source.includes(importStatement)) {
        throw new Error('The expected japanese-transforms helper import was not found.');
    }
    const declarativeHelpers = `
function suffixInflection(input, output, conditionsIn, conditionsOut) {
    return {kind: 'suffix', input, output, conditionsIn, conditionsOut};
}
function wholeWordInflection(input, output, conditionsIn, conditionsOut) {
    return {kind: 'wholeWord', input, output, conditionsIn, conditionsOut};
}`;
    source = source.replace(importStatement, declarativeHelpers);

    const modulePath = path.join(temporaryDirectory, 'japanese-transforms.mjs');
    await writeFile(modulePath, source, 'utf8');
    const module = await import(pathToFileURL(modulePath).href);
    return module.japaneseTransforms;
}

function flattenDescriptor(descriptor) {
    return {
        schemaVersion: 1,
        upstream: {
            repository: 'https://github.com/yomidevs/yomitan',
            commit: upstreamCommit,
            source: sources.japaneseTransforms.path,
        },
        language: descriptor.language,
        conditions: Object.entries(descriptor.conditions).map(([id, condition]) => ({
            id,
            ...condition,
        })),
        transforms: Object.entries(descriptor.transforms).map(([id, transform]) => {
            const {rules, ...metadata} = transform;
            return {id, ...metadata, rules};
        }),
    };
}

async function loadFixtures(temporaryDirectory) {
    const sourcePath = path.join(thirdPartyRoot, sources.japaneseTests.path);
    let source = await readFile(sourcePath, 'utf8');
    source = source.replace(/^import .*;\n/gm, '');
    source = source.replace('const tests = [', 'export const tests = [');
    const runnerIndex = source.indexOf('\nconst languageTransformer = new LanguageTransformer();');
    if (runnerIndex < 0 || !source.includes('export const tests = [')) {
        throw new Error('The expected japanese transform fixture structure was not found.');
    }
    source = source.slice(0, runnerIndex);

    const modulePath = path.join(temporaryDirectory, 'japanese-transform-fixtures.mjs');
    await writeFile(modulePath, source, 'utf8');
    const module = await import(pathToFileURL(modulePath).href);
    return {
        schemaVersion: 1,
        upstreamCommit,
        groups: module.tests,
    };
}

async function writeCanonicalJSON(outputPath, value) {
    await writeFile(outputPath, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
}
