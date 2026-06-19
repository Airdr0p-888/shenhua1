const fs = require('fs');
const path = require('path');

const SOL_FILE = path.join(__dirname, 'ModaMintToken.sol');
const OUTPUT_JSON = path.join(__dirname, 'compile_output.json');

const source = fs.readFileSync(SOL_FILE, 'utf8');

const input = {
  language: 'Solidity',
  sources: {
    'ModaMintToken.sol': {
      content: source
    }
  },
  settings: {
    optimizer: {
      enabled: true,
      runs: 200
    },
    viaIR: true,
    evmVersion: 'paris',
    outputSelection: {
      '*': {
        '*': ['abi', 'evm.bytecode.object', 'evm.deployedBytecode.object']
      }
    }
  }
};

const inputFile = path.join(__dirname, 'stdin_input.json');
fs.writeFileSync(inputFile, JSON.stringify(input), 'utf8');
console.log('Input JSON written to', inputFile);
console.log('Now run: npx solc@0.8.27 --standard-json < stdin_input.json > compile_output.json');
