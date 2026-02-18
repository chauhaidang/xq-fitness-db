#!/usr/bin/env node

/**
 * Script to check which packages have version changes
 * Outputs JSON array of changed package names
 */

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const args = process.argv.slice(2);
const targetFile = args[0]; // Optional: path to specific package.json

let versionChanged = false;
let changedPackages = [];

if (targetFile) {
  // Mode 1: Check specific file
  checkFile(targetFile);
} else {
  // Mode 2: Check all packages in ../packages
  const packagesDir = path.join(__dirname, '..', 'packages');
  if (fs.existsSync(packagesDir)) {
    const packageDirs = fs.readdirSync(packagesDir, { withFileTypes: true })
      .filter(dirent => dirent.isDirectory())
      .map(dirent => dirent.name);

    for (const pkgName of packageDirs) {
      checkFile(path.join(packagesDir, pkgName, 'package.json'), pkgName);
    }
  } else {
    console.error(`Packages directory not found: ${packagesDir}`);
  }
}

function checkFile(filePath, pkgNameOverride) {
  if (!fs.existsSync(filePath)) {
    return;
  }

  try {
    const pkgJson = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    const versionNow = pkgJson.version;
    const pkgName = pkgNameOverride || pkgJson.name;

    if (!versionNow) {
      return;
    }

    // Resolve path relative to git root for git command
    // Valid for both absolute and relative paths
    const gitRoot = execSync('git rev-parse --show-toplevel', { encoding: 'utf8' }).trim();
    const absolutePath = path.resolve(filePath);
    const relPath = path.relative(gitRoot, absolutePath);

    // Try to get previous version from git
    let versionPrev = '';
    try {
      const prevCommit = execSync('git rev-parse HEAD^1 2>/dev/null || echo ""', { encoding: 'utf8' }).trim();

      if (prevCommit) {
        try {
          const prevPkgJson = execSync(`git show ${prevCommit}:${relPath} 2>/dev/null`, { encoding: 'utf8' });
          const prevPkg = JSON.parse(prevPkgJson);
          versionPrev = prevPkg.version || '';
        } catch (e) {
          // File didn't exist in previous commit or parsing failed
        }
      }
    } catch (e) {
      // General git error
    }

    if (versionNow !== versionPrev) {
      versionChanged = true;
      changedPackages.push(pkgName);
      console.log(`Package ${pkgName} version changed: ${versionPrev || '(new)'} -> ${versionNow}`);

      // Output extracted version for workflow if checking single file
      if (targetFile) {
        const githubOutput = process.env.GITHUB_OUTPUT;
        if (githubOutput) {
          fs.appendFileSync(githubOutput, `version=${versionNow}\n`);
        }
      }
    } else {
      console.log(`Package ${pkgName} version unchanged: ${versionNow}`);
    }
  } catch (e) {
    console.error(`Error processing ${filePath}:`, e.message);
  }
}

// Output JSON to stdout
const result = {
  version_changed: versionChanged,
  changed_packages: changedPackages
};
console.log(JSON.stringify(result));

// GitHub Actions Output
const githubOutput = process.env.GITHUB_OUTPUT;
if (githubOutput) {
  fs.appendFileSync(githubOutput, `version_changed=${versionChanged}\n`);
  fs.appendFileSync(githubOutput, `changed_packages=${JSON.stringify(changedPackages)}\n`);
}

