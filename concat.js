#!/usr/bin/env node
// @ts-nocheck

const fs = require('fs');
const path = require('path');
const child_process = require('child_process');

// Attempt to load Babel parser for AST-based summarization.
let babelParser = null;
try {
  babelParser = require('@babel/parser');
  // Minimal logging on startup
} catch (e) {
  console.warn(
    'Warning: @babel/parser not found. Falling back to native summarization for JS/TS files.'
  );
}

// CLI flag for summarization using native process.argv.
const shouldSummarize = process.argv.includes('--noSummarize') ? false : true;

// Configuration
const ALLOWED_EXTENSIONS = [
  '.js',
  '.ts',
  '.jsx',
  '.tsx',
  '.cjs',
  '.mjs',
  '.yml',
  '.yaml',
  '.toml',
  '.prettierrc',
  '.eslintrc',
  '.babelrc',
  '.gitignore',
  '.dockerignore',
  '.npmignore',
  '.editorconfig',
  '.mdx',
  '.json5',
  '.json',
  '.html',
  '.css',
  '.md',
  '.txt',
  '.py',
  '.java',
  '.c',
  '.cpp',
  '.sh',
  '.rb',
  '.go',
  '.rs',
];
const MAX_FILE_SIZE = 500 * 1024; // 500 KB limit
const LARGE_FILE_LINE_THRESHOLD = 300; // Lines threshold to trigger summarization
const OUTPUT_FILE_MD = 'concat.md';

// Helper: Check if file should be skipped.
function shouldSkip(filePath) {
  const resolvedFilePath = path.resolve(filePath);
  if (resolvedFilePath === path.resolve(__filename)) return true;
  if (path.basename(filePath) === OUTPUT_FILE_MD) return true;

  // Instead of checking filePath.includes('test'), split the path and check each part.
  const pathParts = filePath.split(path.sep);
  const skipDirs = ['node_modules', 'dist', 'build', 'coverage', 'test', 'spec'];
  if (pathParts.some(part => skipDirs.includes(part))) return true;

  const skipFiles = [
    'package-lock.json',
    'yarn.lock',
    'pnpm-lock.yaml',
    'bun.lockb',
    'Gemfile.lock',
    'Gemfile',
    'concat.js',
    'concat.md',
    'concat.txt',
  ];
  if (skipFiles.includes(path.basename(filePath))) return true;
  return false;
}

// Helper: Check allowed extension.
function isAllowedExtension(filePath) {
  if (ALLOWED_EXTENSIONS.length === 0) return true;
  return ALLOWED_EXTENSIONS.includes(path.extname(filePath));
}

// Recursively scan for file paths.
function getAllFilePaths(directory) {
  let filePaths = [];
  const items = fs.readdirSync(directory, { withFileTypes: true });
  items.forEach(item => {
    const fullPath = path.resolve(directory, item.name);
    if (shouldSkip(fullPath)) return;
    if (item.isDirectory()) {
      filePaths = filePaths.concat(getAllFilePaths(fullPath));
    } else {
      if (isAllowedExtension(fullPath)) {
        filePaths.push(fullPath);
      }
    }
  });
  return filePaths;
}

// Build a repository tree to generate a Table of Contents.
let repoTree = { files: [] };
function addToTree(relativePath) {
  const parts = relativePath.split(path.sep);
  let current = repoTree;
  parts.forEach((part, idx) => {
    if (idx === parts.length - 1) {
      if (!current.files) current.files = [];
      current.files.push(part);
    } else {
      if (!current[part]) {
        current[part] = { files: [] };
      }
      current = current[part];
    }
  });
}

function generateTreeMarkdown(tree, prefix = '') {
  let lines = [];
  Object.keys(tree)
    .sort()
    .forEach(key => {
      if (key === 'files') return;
      lines.push(prefix + '- **' + key + '/**');
      lines.push(...generateTreeMarkdown(tree[key], prefix + '  '));
    });
  if (tree.files && tree.files.length > 0) {
    tree.files.sort().forEach(file => {
      lines.push(prefix + '- ' + file);
    });
  }
  return lines;
}

// Retrieve the last git commit message for a file.
function getGitLastCommit(filePath) {
  try {
    const commit = child_process.execSync(
      `git log -1 --pretty=format:"%s" -- "${filePath}"`,
      { encoding: 'utf8' }
    );
    return commit;
  } catch (error) {
    return null;
  }
}

// AST-based summarization for JS/TS files.
function astSummarizeContent(content, ext) {
  if (!babelParser) {
    return (
      content.split('\n').slice(0, LARGE_FILE_LINE_THRESHOLD).join('\n') +
      '\n... [Content Summarized]'
    );
  }
  try {
    const ast = babelParser.parse(content, {
      sourceType: 'module',
      plugins: ['jsx', 'typescript'],
    });
    let summaryLines = [];
    ast.program.body.forEach(node => {
      if (node.type === 'FunctionDeclaration' && node.id && node.id.name) {
        summaryLines.push(`function ${node.id.name}(...) { ... }`);
      } else if (node.type === 'ClassDeclaration' && node.id && node.id.name) {
        summaryLines.push(`class ${node.id.name} { ... }`);
      } else if (node.type === 'VariableDeclaration') {
        node.declarations.forEach(decl => {
          if (
            decl.init &&
            (decl.init.type === 'ArrowFunctionExpression' ||
              decl.init.type === 'FunctionExpression')
          ) {
            summaryLines.push(`const ${decl.id.name} = (...) => { ... }`);
          }
        });
      }
    });
    if (summaryLines.length === 0) {
      summaryLines = content.split('\n').slice(0, LARGE_FILE_LINE_THRESHOLD);
    }
    return summaryLines.join('\n') + '\n... [AST-based Summary]';
  } catch (err) {
    return (
      content.split('\n').slice(0, LARGE_FILE_LINE_THRESHOLD).join('\n') +
      '\n... [Content Summarized]'
    );
  }
}

// General summarization function.
function summarizeContent(content, ext) {
  const lines = content.split('\n');
  if (lines.length < LARGE_FILE_LINE_THRESHOLD) return content;
  if (['.js', '.ts', '.jsx', '.tsx'].includes(ext)) {
    return astSummarizeContent(content, ext);
  }
  return (
    lines.slice(0, LARGE_FILE_LINE_THRESHOLD).join('\n') +
    '\n... [Content Summarized]'
  );
}

// Process a single file and return Markdown-formatted content.
function processFile(filePath, rootDir) {
  let fileData = '';
  try {
    // Compute the relative path based on the repository root.
    const relativePath = path.relative(rootDir, filePath);
    addToTree(relativePath);
    const stats = fs.statSync(filePath);
    const fileSize = stats.size;
    const modifiedDate = stats.mtime;
    const fileContents = fs.readFileSync(filePath, 'utf8');
    const ext = path.extname(filePath);
    const linesCount = fileContents.split('\n').length;
    const isLargeFile =
      fileSize > MAX_FILE_SIZE || linesCount > LARGE_FILE_LINE_THRESHOLD;
    let processedContent = fileContents;
    if (shouldSummarize && isLargeFile) {
      processedContent = summarizeContent(fileContents, ext);
    }
    const lastCommit = getGitLastCommit(filePath);
    fileData += `\n\n## File: \`${relativePath}\`\n`;
    fileData += `- **File Size:** ${fileSize} bytes\n`;
    fileData += `- **Last Modified:** ${modifiedDate}\n`;
    if (lastCommit) {
      fileData += `- **Last Commit:** ${lastCommit}\n`;
    }
    if (shouldSummarize && isLargeFile) {
      fileData += `- **Note:** Content has been summarized for brevity.\n`;
    }
    fileData += `\n\`\`\`\n${processedContent}\n\`\`\`\n`;
  } catch (error) {
    throw new Error(`Error processing file ${filePath}: ${error.message}`);
  }
  return fileData;
}

function main() {
  const startTime = Date.now();
  let filesMarkdown = '';
  let processedCount = 0;
  let errorCount = 0;

  // Use process.cwd() as the repository root directory.
  const rootDir = process.cwd();
  // Get list of file paths to process.
  const allFiles = getAllFilePaths(rootDir);
  const totalFiles = allFiles.length;

  // Process each file, passing the repository root.
  allFiles.forEach(filePath => {
    try {
      const fileData = processFile(filePath, rootDir);
      filesMarkdown += fileData;
      processedCount++;
    } catch (err) {
      errorCount++;
      console.error(`Error processing file ${filePath}: ${err.message}`);
    }
  });

  // Generate repository structure for Table of Contents.
  const tocLines = generateTreeMarkdown(repoTree);
  const tocMarkdown = `# Repository Structure\n\n${tocLines.join('\n')}\n\n---\n`;

  // Optionally include additional docs.
  let additionalDocs = '';
  const docFiles = ['README.md', 'CONTRIBUTING.md', 'CHANGELOG.md'];
  docFiles.forEach(doc => {
    const docPath = path.join(rootDir, doc);
    if (fs.existsSync(docPath)) {
      const docContent = fs.readFileSync(docPath, 'utf8');
      additionalDocs += `\n\n# ${doc}\n\n${docContent}\n\n---\n`;
    }
  });

  let outputData = tocMarkdown + additionalDocs + filesMarkdown;
  outputData = outputData.replace(/\n{3,}/g, '\n\n');

  // Write the concatenated markdown to file.
  try {
    fs.writeFileSync(OUTPUT_FILE_MD, outputData, 'utf8');
  } catch (error) {
    console.error(`Error writing markdown file: ${error.message}`);
  }
  const endTime = Date.now();
  const duration = ((endTime - startTime) / 1000).toFixed(2);

  // Final summary report.
  console.log('\n=== Processing Summary ===');
  console.log(`Total files found: ${totalFiles}`);
  console.log(`Successfully processed: ${processedCount}`);
  console.log(`Files with errors: ${errorCount}`);
  console.log(`Total processing time: ${duration} seconds`);
  console.log(`\nConcatenated markdown file written to ${OUTPUT_FILE_MD}`);
}

main();
