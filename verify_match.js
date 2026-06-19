const fs = require('fs');

// 读取 admin.html，找出所有 targetContract.XXX 调用
const html = fs.readFileSync('admin.html', 'utf8');
const re = /targetContract\.([a-zA-Z0-9_]+)\s*\(/g;
const calledFns = new Set();
let m;
while ((m = re.exec(html)) !== null) {
  calledFns.add(m[1]);
}

console.log('=== admin.html 调用的合约函数 ===');
for (const fn of calledFns) console.log(' -', fn);

// 读取 ABI
const dataContent = fs.readFileSync('contract_data.js', 'utf8');
// 提取 ABI JSON（找到 "ABI": [...] 部分）
const abiStart = dataContent.indexOf('"ABI":');
if (abiStart === -1) { console.error('无法找到 ABI'); process.exit(1); }
// 找到 JSON 数组的开始和结束
let depth = 0;
let inString = false;
let escapeNext = false;
let jsonStart = -1;
let jsonEnd = -1;
for (let i = abiStart + 5; i < dataContent.length; i++) {
  const ch = dataContent[i];
  if (escapeNext) { escapeNext = false; continue; }
  if (ch === '\\') { escapeNext = true; continue; }
  if (ch === '"' && !escapeNext) { inString = !inString; continue; }
  if (!inString) {
    if (ch === '[') { if (depth === 0) jsonStart = i; depth++; }
    if (ch === ']') { depth--; if (depth === 0) { jsonEnd = i; break; } }
  }
}
if (jsonStart === -1 || jsonEnd === -1) { console.error('无法解析 ABI JSON'); process.exit(1); }
const abi = JSON.parse(dataContent.slice(jsonStart, jsonEnd + 1));

const abiFns = new Set(abi.filter(x => x.type === 'function').map(x => x.name));
// 加上 public 变量自动生成的 getter（在 ABI 中 type 为 function，stateMutability view）
// 这些已经在 abi 里了

console.log('\n=== 函数匹配检查 ===');
let allOk = true;
for (const fn of calledFns) {
  if (abiFns.has(fn)) {
    console.log('✅', fn, '- ABI 中存在');
  } else {
    console.log('❌', fn, '- ABI 中不存在！');
    allOk = false;
  }
}
console.log('\n=== 总结 ===');
if (allOk) {
  console.log('✅ 所有函数调用都与 ABI 匹配！');
} else {
  console.log('❌ 有函数不匹配，请检查上方 ❌ 项');
}
