# B-Evoke: Blockchain EVOKE Implementation

## What is B-Evoke?

B-Evoke implements the **EVOKE paper's credential revocation system** for IoT devices using blockchain and zero-knowledge proofs. It replaces EVOKE's centralized trusted third party with decentralized blockchain verification.

## Quick Start 🚀

### 1. Verify System is Ready

```bash
# Quick health check (5 seconds)
./verify.sh
```

### 2. Run Tests

```bash
# Complete end-to-end EVOKE test suite (4 scenarios)
# - Baby Jubjub ECC operations
# - Device revocation & witness management
# - SNARK proof generation & verification
# - Batch operations
node test-evoke.js

# Solidity tests (29 comprehensive tests)
~/.foundry/bin/forge test --via-ir
```

## How It Works

### Core Concept
EVOKE uses an **ECC accumulator** to track revoked IoT device credentials:
- **Accumulator**: A single elliptic curve point that represents ALL revoked devices
- **Witness**: Proof that a device is (or isn't) in the revocation list
- **SNARK Proof**: Zero-knowledge proof verifying revocation status

### Key Operations

1. **Revoke a Device**
   - Add device to accumulator: `ACC_new = ACC_old + g^deviceID`
   - Store witness for membership proof
   - Update all existing witnesses

2. **Check Revocation Status**
   - If revoked → Generate membership proof
   - If valid → Device not in revocation list

3. **Batch Revocation**
   - Revoke multiple devices efficiently
   - Update all witnesses in single pass

## Technical Details

### Implementation
- **Curve**: Baby Jubjub (SNARK-friendly elliptic curve)
- **Proof System**: Groth16 zero-knowledge proofs
- **Constraints**: 1531 for ECC, 1530 for membership
- **Performance**: ~700ms proof generation, ~196k gas verification

### Architecture
```
IoT Device (1.5KB storage)
    ↓
EVOKE Service (proof generation)
    ↓
Blockchain (verification & state)
```

## Project Structure

```
b-evoke/
├── circuits/
│   ├── ecc_accumulator.circom            # ECC operations (1531 constraints)
│   └── evoke_membership_simple.circom    # Membership proofs (1530 constraints)
├── src/
│   ├── B_Evoke_Registry_ECC.sol          # Device registry (with ECC)
│   └── ECCGroth16Verifier.sol            # SNARK verifier
├── test/
│   └── B_Evoke_Tests.t.sol               # Comprehensive test suite (29 tests)
├── test-evoke.js                         # JavaScript test suite (4 scenarios)
├── verify.sh                             # System verification
├── README.md                             # This file
├── CONTEXT_SUMMARY.md                    # Project context
├── EVOKE_IMPLEMENTATION_COMPLETE.md      # Full EVOKE details
├── ECC_IMPLEMENTATION_REPORT.md          # ECC documentation
├── TECHNICAL_EXPLANATION.md              # How it works
├── PROJECT_ACHIEVEMENT_REPORT.md         # Project history
└── PROJECT_STRUCTURE.md                  # File organization
```

## Verification

### Check Circuit Information

```bash
# ECC accumulator circuit (1531 constraints)
npx snarkjs r1cs info circuits/ecc/ecc_accumulator.r1cs

# Membership proof circuit (1530 constraints)
npx snarkjs r1cs info circuits/evoke/evoke_membership_simple.r1cs
```

### Run Smart Contract Tests

```bash
# Run all 29 Solidity tests
~/.foundry/bin/forge test --via-ir

# Run specific test file
~/.foundry/bin/forge test --via-ir --match-contract B_Evoke_Extended_Tests
```

## What Makes This Special?

1. **Elliptic Curves**: Uses actual EC operations, not hash functions
2. **EVOKE Compliant**: Implements exact paper specifications
3. **Production Ready**: Complete with circuits, proofs, and verification
4. **Efficient**: Constant 1.5KB storage per IoT device
5. **Decentralized**: Blockchain replaces centralized trust
6. **Thoroughly Tested**: 29 Solidity tests + comprehensive JavaScript test suites

## Test Coverage

### Solidity Tests (29 tests, all passing)
- **SNARK Verification** (3 tests): Valid proofs, invalid proofs, wrong public signals
- **Registration** (5 tests): Max DID, empty DID, zero address, double registration, sequential
- **Revocation** (9 tests): Access control, batch operations (up to 100 devices), edge cases
- **Witness Updates** (4 tests): Valid/invalid updates, multiple sequential updates
- **Membership Verification** (3 tests): Without revocation, invalid witness, non-existent device
- **Gas Optimization** (3 tests): Registration (<200k), revocation (<150k), verification (<100k)
- **State Consistency** (2 tests): Accumulator integrity, statistics accuracy

### JavaScript Tests
- **test-evoke.js**: End-to-end EVOKE operations (4 scenarios)

## Documentation

- `EVOKE_IMPLEMENTATION_COMPLETE.md` - Full implementation details
- `ECC_IMPLEMENTATION_REPORT.md` - ECC accumulator documentation
- `TECHNICAL_EXPLANATION.md` - How everything works
- `PROJECT_ACHIEVEMENT_REPORT.md` - Development journey

## Requirements

- Node.js v22.10.0+
- Foundry (for smart contract tests)
- SnarkJS (globally installed for circuit operations)

## License

MIT