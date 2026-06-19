const fs = require('fs');
const { execSync } = require('child_process');

const source = fs.readFileSync('ModaMintToken.sol', 'utf8');
const input = {
  language: 'Solidity',
  sources: { 'ModaMintToken.sol': { content: source } },
  settings: {
    optimizer: { enabled: true, runs: 200 },
    viaIR: true,
    evmVersion: 'paris',
    outputSelection: { '*': { '*': ['abi', 'evm.bytecode.object'] } }
  }
};

const tmpFile = 'stdin_input.json';
fs.writeFileSync(tmpFile, JSON.stringify(input));

try {
  const result = execSync(`npx solc@0.8.35 --standard-json < "${tmpFile}"`, {
    encoding: 'utf8',
    stdio: ['pipe', 'pipe', 'pipe'],
    maxBuffer: 10 * 1024 * 1024,
    timeout: 120000
  });
  // 打印前 500 个字符，看看格式
  console.log('=== STDOUT 前500字符 ===');
  console.log(result.stdout ? result.stdout.slice(0, 500) : result.slice(0, 500));
  console.log('=== STDOUT 长度 ===', (result.stdout || result).length);
} catch(e) {
  const out = e.stdout || '';
  console.log('=== 错误时 STDOUT 前500字符 ===');
  console.log(out.slice(0, 500));
  console.log('=== STDERR ===', (e.stderr || '').slice(0, 200));
}
