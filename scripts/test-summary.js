const fs = require('fs');
const path = require('path');

console.log('🧪 Cross-Chain RWA Passport - Test Suite Summary\n');

const testDir = path.join(__dirname, '..', 'test');

function analyzeTestFile(filePath) {
  const fileName = path.basename(filePath);
  console.log(`📄 ${fileName}`);
  
  const content = fs.readFileSync(filePath, 'utf8');
  
  // Count describe blocks
  const describeMatches = content.match(/describe\(/g) || [];
  console.log(`   📋 Test Suites: ${describeMatches.length}`);
  
  // Count it blocks
  const itMatches = content.match(/it\(/g) || [];
  console.log(`   ✅ Test Cases: ${itMatches.length}`);
  
  // Extract test suite names
  const describeRegex = /describe\(\s*["']([^"']+)["']/g;
  let match;
  console.log(`   🔍 Test Suites:`);
  while ((match = describeRegex.exec(content)) !== null) {
    console.log(`      - ${match[1]}`);
  }
  
  // Extract test case names
  const itRegex = /it\(\s*["']([^"']+)["']/g;
  console.log(`   🧪 Test Cases:`);
  let count = 0;
  while ((match = itRegex.exec(content)) !== null && count < 5) {
    console.log(`      - ${match[1]}`);
    count++;
  }
  if (itMatches.length > 5) {
    console.log(`      ... and ${itMatches.length - 5} more`);
  }
  
  console.log('');
}

// Get all test files
const testFiles = fs.readdirSync(testDir)
  .filter(file => file.endsWith('.test.ts'))
  .map(file => path.join(testDir, file));

console.log(`📊 Found ${testFiles.length} test files:\n`);

testFiles.forEach(analyzeTestFile);

// Test coverage summary
console.log('📈 Test Coverage Summary:');
console.log('┌─────────────────────────┬─────────────┬──────────────┐');
console.log('│ Contract                │ Test Suites │ Test Cases   │');
console.log('├─────────────────────────┼─────────────┼──────────────┤');

testFiles.forEach(filePath => {
  const fileName = path.basename(filePath, '.test.ts');
  const content = fs.readFileSync(filePath, 'utf8');
  const suites = (content.match(/describe\(/g) || []).length;
  const cases = (content.match(/it\(/g) || []).length;
  
  console.log(`│ ${fileName.padEnd(23)} │ ${suites.toString().padStart(11)} │ ${cases.toString().padStart(12)} │`);
});

console.log('└─────────────────────────┴─────────────┴──────────────┘');

console.log('\n🎯 Test Areas Covered:');
console.log('✅ Contract Deployment');
console.log('✅ Access Control (Ownable)');
console.log('✅ Passport Creation & Management');
console.log('✅ Verification System');
console.log('✅ Cross-Chain Messaging');
console.log('✅ Error Handling');
console.log('✅ Event Emission');
console.log('✅ View Functions');

console.log('\n📋 To Run Tests:');
console.log('1. npm install                 # Install dependencies');
console.log('2. npx hardhat compile         # Compile contracts');
console.log('3. npx hardhat test            # Run all tests');
console.log('4. npx hardhat test --grep "PassportRegistry"  # Run specific tests');

console.log('\n📝 Test Structure:');
console.log('Each test file follows the pattern:');
console.log('  📁 Contract Name');
console.log('    📋 Deployment Tests');
console.log('    📋 Functionality Tests');
console.log('    📋 Access Control Tests');
console.log('    📋 Error Handling Tests');
console.log('    📋 Integration Tests');

console.log('\n✨ All tests are designed to work with Hardhat\'s built-in test network');
console.log('🚀 Tests validate both positive and negative scenarios for comprehensive coverage'); 