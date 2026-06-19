const fs = require('fs');
const path = require('path');

// 读取 contract_data.js 并提取 ABI
const content = fs.readFileSync('contract_data.js', 'utf8');

// 用 eval 安全地提取 CONTRACT_DATA（仅提取 ABI）
const VM = require('vm');
const sandbox = { console, JSON, module: { exports: {} } };
try {
  VM.createContext(sandbox);
  VM.runInContext(content, sandbox);
  var CONTRACT_DATA = sandbox.CONTRACT_DATA || sandbox.module.exports.CONTRACT_DATA;
} catch(e) {
  // 如果上面失败，手动解析 JSON 部分
  const jsonMatch = content.match(/"ABI":\s*(\[[\s\S]*?\])\s*,\s*"BYTECODE"/);
  if (jsonMatch) {
    CONTRACT_DATA = { ABI: JSON.parse(jsonMatch[1]) };
  } else {
    console.error('无法解析 contract_data.js');
    process.exit(1);
  }
}

const abi = CONTRACT_DATA.ABI;
const functions = abi.filter(x => x.type === 'function').map(x => x.name);
const readFunctions = abi.filter(x => x.type === 'function' && x.stateMutability === 'view').map(x => x.name);
const writeFunctions = abi.filter(x => x.type === 'function' && x.stateMutability !== 'view').map(x => x.name);

console.log('=== ABI 概览 ===');
console.log('总函数数:', functions.length);
console.log('\n=== 关键函数检查 ===');
const keyFns = ['mint', 'addWhitelist', 'removeWhitelist', 'setMintPrice', 'setWhitelistMintOnly', 'enableTrading', 'withdrawPresaleBNB', 'withdrawBNB'];
keyFns.forEach(fn => {
  console.log(fn + ':', functions.includes(fn) ? '✅' : '❌ 缺失');
});

console.log('\n=== mint 函数签名（关键！）===');
const mintFn = abi.find(x => x.name === 'mint' && x.type === 'function');
if (mintFn) {
  console.log('name:', mintFn.name);
  console.log('inputs:', JSON.stringify(mintFn.inputs));
  console.log('stateMutability:', mintFn.stateMutability);
  if (!mintFn.inputs || mintFn.inputs.length === 0) {
    console.log('✅ mint() 无参数，与前端 admin.html 修复匹配！');
  } else {
    console.log('❌ mint() 有参数，前端需要检查！');
  }
} else {
  console.log('❌ mint 函数未找到！');
}

console.log('\n=== hasMinted mapping ===');
const hasMintedFn = abi.find(x => x.name === 'hasMinted');
if (hasMintedFn) {
  console.log('✅ hasMinted 在 ABI 中（自动生成 getter）');
  console.log(JSON.stringify(hasMintedFn, null, 2));
} else {
  console.log('ℹ️  hasMinted 是 mapping，ABI 中无直接函数（正常）');
}

console.log('\n=== 字节码 ===');
const bytecode = CONTRACT_DATA.BYTECODE || content.match(/BYTECODE:\s*"(0x[0-9a-fA-F]+)"/)?.[1];
if (bytecode) {
  console.log('字节码长度:', bytecode.length, '字符（含 0x）');
  console.log('字节码前 20 字符:', bytecode.slice(0, 20));
}
