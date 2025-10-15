# B-Evoke Technical Explanation

## Overview

B-Evoke implements EVOKE's credential revocation system for IoT devices using blockchain and elliptic curve cryptography. This document explains the technical concepts in detail.

## The Problem

IoT devices have severe constraints:
- **Limited Storage**: Only ~1.5KB available
- **Limited Processing**: Can't handle large computations
- **Intermittent Connectivity**: May be offline frequently

Traditional revocation methods (CRL, OCSP) don't work because:
- Certificate Revocation Lists grow unbounded
- Online checking requires constant connectivity
- Storage requirements exceed device capacity

## EVOKE's Solution

EVOKE uses **cryptographic accumulators** - a way to compress unlimited revoked credentials into a single fixed-size value.

## Cryptographic Accumulators

### What is an Accumulator?

An accumulator is like a mathematical "container" that:
- Takes unlimited inputs
- Produces a single fixed-size output
- Allows membership proofs without revealing all elements

### ECC-Based Accumulator (What We Use)

We use elliptic curve cryptography on the Baby Jubjub curve:

```
Accumulator = g^(element1) * g^(element2) * ... * g^(elementN)
```

Where:
- `g` is the generator point on the curve
- Elements are device IDs
- Multiplication happens on the elliptic curve

### How It Works

#### 1. Initial State
```
Accumulator = Identity Point (0,1)
No devices revoked
```

#### 2. Revoking Device 123
```
New_Accumulator = Old_Accumulator + g^123
Witness_123 = Old_Accumulator (before adding 123)
```

#### 3. Revoking Device 456
```
New_Accumulator = Old_Accumulator + g^456
Witness_456 = Old_Accumulator (before adding 456)
Update Witness_123 = Witness_123 + g^456
```

## Key Concepts

### 1. Accumulator
- A point on the elliptic curve (x,y coordinates)
- Represents ALL revoked devices
- Fixed size: 512 bits (two 256-bit coordinates)
- Public value stored on blockchain

### 2. Witness
- Proof that a device is in the accumulator
- Also a point on the curve
- Equation: `Accumulator = Witness + g^device`
- Private value held by revoked device

### 3. Membership Proof
To prove device 123 is revoked:
```
Public: Current Accumulator
Private: device=123, Witness_123
Prove: Accumulator == Witness_123 + g^123
```

### 4. Witness Updates
When new device is revoked, ALL witnesses must update:
```
For each existing witness W:
  W_new = W_old + g^new_device
```

## Baby Jubjub Curve

We use Baby Jubjub because it's "SNARK-friendly":
- Defined over the BN254 scalar field
- Efficient inside circuits
- Secure for cryptographic use

Curve equation: `ax² + y² = 1 + dx²y²`
- a = 168700
- d = 168696

## SNARK Proofs

### What are SNARKs?

Zero-Knowledge Succinct Non-Interactive Arguments of Knowledge:
- **Zero-Knowledge**: Prove something without revealing secrets
- **Succinct**: Small proof size (~1KB)
- **Non-Interactive**: No back-and-forth communication
- **Argument of Knowledge**: Computationally sound

### Our Circuits

#### 1. ECC Accumulator Circuit (`ecc_accumulator.circom`)
- **Purpose**: Update accumulator with new element
- **Constraints**: 1531
- **Operations**: Scalar multiplication + point addition

#### 2. Membership Circuit (`evoke_membership_simple.circom`)
- **Purpose**: Prove device is in accumulator
- **Constraints**: 1530
- **Equation**: Verify `A = W + g^element`

### Groth16 Proof System

We use Groth16 because:
- Smallest proofs (~1KB)
- Fast verification (~196k gas)
- Well-established security

## Implementation Flow

### 1. Device Revocation

```javascript
revokeDevice(deviceId) {
    // Store current accumulator as witness
    witness[deviceId] = accumulator

    // Update accumulator
    accumulator = accumulator + g^deviceId

    // Update all existing witnesses
    for each existing device:
        witness[device] = witness[device] + g^deviceId
}
```

### 2. Status Check

```javascript
checkStatus(deviceId) {
    if (deviceId in revokedList) {
        // Generate membership proof
        proof = prove(accumulator == witness[deviceId] + g^deviceId)
        return REVOKED with proof
    } else {
        return VALID
    }
}
```

### 3. Batch Revocation

```javascript
batchRevoke(deviceIds[]) {
    for each deviceId:
        witness[deviceId] = accumulator
        accumulator = accumulator + g^deviceId
        updateAllWitnesses(deviceId)
}
```

## Storage Requirements

### IoT Device
- Device ID: 32 bytes
- Current Accumulator: 64 bytes (x,y coordinates)
- Witness (if revoked): 64 bytes
- **Total**: ~160 bytes << 1.5KB limit ✓

### Blockchain
- Global Accumulator: 64 bytes
- Registry mappings: O(n) for n devices
- Proof verification: No storage (computation only)

### Service Provider
- All witnesses: 64 bytes × number of revoked devices
- Proving keys: ~50MB (one-time setup)
- Verification keys: ~1KB

## Security Guarantees

### Based on Discrete Logarithm Problem
Given `Y = g^x`, finding `x` is computationally hard

### Properties
1. **Collision Resistance**: Can't find two sets with same accumulator
2. **Soundness**: Can't create false membership proofs
3. **Zero-Knowledge**: Proofs don't reveal witness or device ID
4. **Binding**: Accumulator uniquely determines member set

## Performance

### Proof Generation
- ECC accumulator update: ~700ms
- Membership proof: ~700ms
- Dominated by scalar multiplication

### Verification
- On-chain: ~196,000 gas
- Off-chain: <100ms
- Uses Ethereum precompiles

### Witness Updates
- O(n) for n revoked devices
- ~10ms per update
- Can be parallelized

## Advantages Over Other Systems

### vs Certificate Revocation Lists (CRL)
- CRL: Grows unbounded
- EVOKE: Fixed size accumulator

### vs Online Certificate Status Protocol (OCSP)
- OCSP: Requires connectivity
- EVOKE: Works offline with witness

### vs Bloom Filters
- Bloom: Probabilistic (false positives)
- EVOKE: Deterministic with proofs

## Blockchain Integration

### Why Blockchain?
- Replaces centralized trusted third party
- Immutable revocation history
- Transparent accumulator updates
- Decentralized verification

### Smart Contracts
1. **Registry Contract**: Manages device registrations
2. **Verifier Contract**: Verifies SNARK proofs on-chain

### Gas Optimization
- Proof verification uses precompiles: `ecAdd`, `ecMul`, `ecPairing`
- Batch updates save gas vs individual transactions
- L2 deployment reduces costs 100x

## Future Enhancements

### 1. Non-Membership Proofs
Prove device is NOT revoked (more complex than membership)

### 2. Dynamic Accumulator
Support removing devices from revocation list

### 3. Distributed Witness Generation
Multiple parties can generate witnesses

### 4. Threshold Revocation
Require k-of-n authorities to revoke

## Summary

B-Evoke implements EVOKE's vision of efficient credential revocation for IoT devices by:
- Using ECC accumulators for constant-size storage
- Generating SNARK proofs for membership verification
- Leveraging blockchain for decentralized trust
- Meeting IoT constraints (~1.5KB storage)

The system provides cryptographic security while being practical for resource-constrained devices.