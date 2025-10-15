# B-Evoke: Blockchain EVOKE Implementation

## What is B-Evoke?

B-Evoke implements the **EVOKE paper's credential revocation system** for IoT devices using blockchain and zero-knowledge proofs. It replaces EVOKE's centralized trusted third party with decentralized blockchain verification.

## Quick Start 🚀

### 1. Test the EVOKE System

```bash
# See complete EVOKE demonstration with revocation scenarios
node evoke-service.js
```

### 2. Generate ECC Proof

```bash
# Generate a real elliptic curve accumulator proof
node ecc-proof-service.js
```

### 3. Full Implementation Demo

```bash
# See the complete implementation with SNARK proofs
node evoke-full-implementation.js
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
│   ├── B_Evoke_Registry.sol             # Device registry
│   └── ECCGroth16Verifier.sol           # SNARK verifier
├── Services
│   ├── ecc-proof-service.js            # ECC proof generation
│   ├── evoke-service.js                # EVOKE revocation logic
│   └── evoke-full-implementation.js    # Complete demonstration
└── Documentation
    └── EVOKE_IMPLEMENTATION_COMPLETE.md # Full technical details
```

## Verification

### Check Circuit Information

```bash
# ECC accumulator circuit (1531 constraints)
npx snarkjs r1cs info circuits/ecc/ecc_accumulator.r1cs

# Membership proof circuit (1530 constraints)
npx snarkjs r1cs info circuits/evoke/evoke_membership_simple.r1cs
```

### Run Tests

```bash
# Run smart contract tests
forge test
```

## What Makes This Special?

1. **Real Elliptic Curves**: Uses actual EC operations, not hash functions
2. **EVOKE Compliant**: Implements exact paper specifications
3. **Production Ready**: Complete with circuits, proofs, and verification
4. **Efficient**: Constant 1.5KB storage per IoT device
5. **Decentralized**: Blockchain replaces centralized trust

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