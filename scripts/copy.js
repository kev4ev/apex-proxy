#! /usr/bin/env node

const fs = require('fs');
const path = require('path');

const [, , command] = process.argv;

if (command !== 'init') {
    console.error(`Unknown command: ${command || '(none)'}. Usage: npx @machso/apexproxy init`);
    process.exit(1);
}

const cwd = process.cwd();
const sfdxProjectPath = path.join(cwd, 'sfdx-project.json');

const ERROR_MSG =
    'Error: sfdx-project.json must be present in the current directory and must include a default packageDirectory.';

// Read sfdx-project.json
let sfdxProject;
try {
    sfdxProject = JSON.parse(fs.readFileSync(sfdxProjectPath, 'utf8'));
} catch {
    console.error(ERROR_MSG);
    process.exit(1);
}

// Find default package directory
const packageDirectories = sfdxProject.packageDirectories;
const defaultDir =
    Array.isArray(packageDirectories) && packageDirectories.find((d) => d.default === true);

if (!defaultDir) {
    console.error(ERROR_MSG);
    process.exit(1);
}

// Compute source and destination
const srcDir = path.join(__dirname, '..', 'force-app', 'main', 'default', 'classes');
const destDir = path.join(cwd, defaultDir.path, 'main', 'default', 'classes');

// Copy all files from source to destination
fs.mkdirSync(destDir, { recursive: true });
const files = fs.readdirSync(srcDir);
for (const file of files) {
    fs.copyFileSync(path.join(srcDir, file), path.join(destDir, file));
}

console.log(`Successfully copied Apex classes to ${destDir}`);
