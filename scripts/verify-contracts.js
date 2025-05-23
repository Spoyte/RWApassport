const fs = require('fs');
const path = require('path');

// Basic Solidity syntax verification
function verifyContract(filePath) {
  console.log(`🔍 Checking ${path.basename(filePath)}...`);
  
  try {
    const content = fs.readFileSync(filePath, 'utf8');
    
    // Basic syntax checks
    const checks = [
      {
        name: 'SPDX License',
        test: content.includes('// SPDX-License-Identifier:'),
        required: true
      },
      {
        name: 'Pragma directive',
        test: content.includes('pragma solidity'),
        required: true
      },
      {
        name: 'Contract declaration',
        test: content.includes('contract '),
        required: true
      },
      {
        name: 'Balanced braces',
        test: (content.match(/{/g) || []).length === (content.match(/}/g) || []).length,
        required: true
      },
      {
        name: 'Balanced parentheses',
        test: (content.match(/\(/g) || []).length === (content.match(/\)/g) || []).length,
        required: true
      },
      {
        name: 'Import statements',
        test: content.includes('import '),
        required: false
      },
      {
        name: 'Functions defined',
        test: content.includes('function '),
        required: false
      },
      {
        name: 'Events defined',
        test: content.includes('event '),
        required: false
      }
    ];
    
    let passed = 0;
    let failed = 0;
    
    checks.forEach(check => {
      if (check.test) {
        console.log(`  ✅ ${check.name}`);
        passed++;
      } else {
        console.log(`  ${check.required ? '❌' : '⚠️'} ${check.name}`);
        if (check.required) failed++;
      }
    });
    
    // Contract-specific checks
    const fileName = path.basename(filePath, '.sol');
    
    if (fileName === 'PassportRegistry') {
      console.log('  📋 PassportRegistry specific checks:');
      console.log(`    ${content.includes('ERC721') ? '✅' : '❌'} ERC-721 inheritance`);
      console.log(`    ${content.includes('createPassport') ? '✅' : '❌'} createPassport function`);
      console.log(`    ${content.includes('verifyPassport') ? '✅' : '❌'} verifyPassport function`);
    }
    
    if (fileName === 'CCIPGateway') {
      console.log('  🌉 CCIPGateway specific checks:');
      console.log(`    ${content.includes('IRouterClient') ? '✅' : '❌'} CCIP Router integration`);
      console.log(`    ${content.includes('ccipSend') ? '✅' : '❌'} CCIP send function`);
      console.log(`    ${content.includes('ccipReceive') ? '✅' : '❌'} CCIP receive function`);
    }
    
    if (fileName === 'OracleVerifier') {
      console.log('  🔮 OracleVerifier specific checks:');
      console.log(`    ${content.includes('ChainlinkClient') ? '✅' : '❌'} Chainlink Client inheritance`);
      console.log(`    ${content.includes('requestAssetVerification') ? '✅' : '❌'} Verification request function`);
      console.log(`    ${content.includes('AggregatorV3Interface') ? '✅' : '❌'} Price feed integration`);
    }
    
    if (fileName === 'SuzakuIntegration') {
      console.log('  🛡️ SuzakuIntegration specific checks:');
      console.log(`    ${content.includes('registerValidator') ? '✅' : '❌'} Validator registration`);
      console.log(`    ${content.includes('slashValidator') ? '✅' : '❌'} Slashing functionality`);
      console.log(`    ${content.includes('createSecurityAttestation') ? '✅' : '❌'} Security attestation`);
    }
    
    console.log(`  📊 Summary: ${passed} passed, ${failed} critical issues\n`);
    
    return failed === 0;
    
  } catch (error) {
    console.log(`  ❌ Error reading file: ${error.message}\n`);
    return false;
  }
}

// Verify all contracts
console.log('🚀 Cross-Chain RWA Passport - Contract Verification\n');

const contractsDir = path.join(__dirname, '..', 'contracts');
const contracts = [
  'PassportRegistry.sol',
  'CCIPGateway.sol',
  'OracleVerifier.sol',
  'SuzakuIntegration.sol'
];

let allPassed = true;

contracts.forEach(contract => {
  const contractPath = path.join(contractsDir, contract);
  if (fs.existsSync(contractPath)) {
    const passed = verifyContract(contractPath);
    allPassed = allPassed && passed;
  } else {
    console.log(`❌ Contract not found: ${contract}\n`);
    allPassed = false;
  }
});

// Check project structure
console.log('📁 Project Structure Verification:');
const requiredFiles = [
  'package.json',
  'hardhat.config.ts',
  'tsconfig.json',
  'contracts/PassportRegistry.sol',
  'scripts/deploy.ts',
  'test/PassportRegistry.test.ts'
];

requiredFiles.forEach(file => {
  const filePath = path.join(__dirname, '..', file);
  console.log(`  ${fs.existsSync(filePath) ? '✅' : '❌'} ${file}`);
});

// Check package.json dependencies
console.log('\n📦 Dependencies Check:');
const packageJson = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'package.json'), 'utf8'));

const requiredDeps = [
  '@openzeppelin/contracts',
  '@chainlink/contracts',
  'dotenv'
];

const requiredDevDeps = [
  'hardhat',
  '@nomicfoundation/hardhat-toolbox',
  'typescript'
];

requiredDeps.forEach(dep => {
  console.log(`  ${packageJson.dependencies && packageJson.dependencies[dep] ? '✅' : '❌'} ${dep}`);
});

requiredDevDeps.forEach(dep => {
  console.log(`  ${packageJson.devDependencies && packageJson.devDependencies[dep] ? '✅' : '❌'} ${dep} (dev)`);
});

console.log('\n🎯 Overall Status:');
if (allPassed) {
  console.log('✅ All contracts passed basic verification!');
  console.log('🚀 Project is ready for compilation and deployment.');
} else {
  console.log('❌ Some issues detected. Please review the contract code.');
}

console.log('\n📋 Next Steps:');
console.log('1. npm install (install dependencies)');
console.log('2. npx hardhat compile (compile contracts)');
console.log('3. npx hardhat test (run tests)');
console.log('4. npm run deploy:fuji (deploy to testnet)'); 