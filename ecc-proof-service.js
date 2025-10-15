#!/usr/bin/env node

const snarkjs = require("/home/xx/.nvm/versions/node/v22.10.0/lib/node_modules/snarkjs");
const fs = require("fs");
const crypto = require("crypto");

/**
 * Full ECC-based SNARK Proof Generation Service for B-Evoke
 *
 * This uses REAL elliptic curve operations on Baby Jubjub curve:
 * - Accumulator is an actual EC point (x,y coordinates)
 * - Adding elements: ACC_new = ACC_old + g^element
 * - NOT hash-based, but actual curve mathematics
 */
class FullECCAccumulatorProofService {
    constructor() {
        this.wasmPath = "./circuits/ecc/ecc_accumulator_js/ecc_accumulator.wasm";
        this.zkeyPath = "./circuits/ecc/ecc_circuit_final.zkey";

        // Baby Jubjub base point
        this.BASE_POINT = {
            x: "5299619240641551281634865583518297030282874472190772894086521144482721001553",
            y: "16950150798460657717958625567821834550301663161624707787222815936182638968203"
        };

        // Initial accumulator (set to base point initially)
        this.INITIAL_ACC = {
            x: this.BASE_POINT.x,
            y: this.BASE_POINT.y
        };
    }

    /**
     * Generate proof for adding element to ECC accumulator
     * This performs actual elliptic curve point addition
     *
     * @param {Object} oldAccumulator - Current accumulator point {x, y}
     * @param {BigInt} element - Element to add (device ID)
     * @param {BigInt} secret - Random secret for zero-knowledge
     * @returns {Object} Proof and new accumulator point
     */
    async generateECCAddProof(oldAccumulator, element, secret) {
        const input = {
            oldAccX: oldAccumulator.x.toString(),
            oldAccY: oldAccumulator.y.toString(),
            element: element.toString(),
            secret: secret.toString()
        };

        console.log("Generating ECC proof with inputs:");
        console.log("  Old Accumulator Point:");
        console.log("    X:", truncate(oldAccumulator.x.toString()));
        console.log("    Y:", truncate(oldAccumulator.y.toString()));
        console.log("  Element:", element.toString());
        console.log("  Secret:", truncate(secret.toString()));

        try {
            const { proof, publicSignals } = await snarkjs.groth16.fullProve(
                input,
                this.wasmPath,
                this.zkeyPath
            );

            // Format proof for Solidity
            const solidityProof = {
                a: [proof.pi_a[0], proof.pi_a[1]],
                b: [[proof.pi_b[0][1], proof.pi_b[0][0]], [proof.pi_b[1][1], proof.pi_b[1][0]]],
                c: [proof.pi_c[0], proof.pi_c[1]]
            };

            // New accumulator is the output point
            const newAccumulator = {
                x: publicSignals[0],
                y: publicSignals[1]
            };

            return {
                proof: solidityProof,
                publicSignals,
                newAccumulator,
                oldAccumulator
            };
        } catch (error) {
            console.error("Error generating ECC proof:", error);
            throw error;
        }
    }

    /**
     * Verify a proof locally
     */
    async verifyProof(proof, publicSignals) {
        try {
            const vKey = JSON.parse(fs.readFileSync("./circuits/ecc/verification_key.json"));

            // Convert proof back for verification
            const verifyProof = {
                pi_a: [proof.a[0], proof.a[1], "1"],
                pi_b: [[proof.b[0][1], proof.b[0][0]], [proof.b[1][1], proof.b[1][0]], ["1", "0"]],
                pi_c: [proof.c[0], proof.c[1], "1"],
                protocol: "groth16",
                curve: "bn128"
            };

            const res = await snarkjs.groth16.verify(vKey, publicSignals, verifyProof);
            return res;
        } catch (error) {
            console.error("Verification error:", error.message);
            return false;
        }
    }

    /**
     * Generate test inputs
     */
    generateTestInputs() {
        // Start with base point as accumulator
        const oldAccumulator = {
            x: BigInt(this.INITIAL_ACC.x),
            y: BigInt(this.INITIAL_ACC.y)
        };

        // Device element to add
        const element = BigInt("123456789");

        // Random secret for ZK
        const secret = BigInt('0x' + crypto.randomBytes(16).toString('hex')) %
                      BigInt("21888242871839275222246405745257275088548364400416034343698204186575808495617");

        return { oldAccumulator, element, secret };
    }
}

function truncate(str) {
    if (str.length > 20) {
        return str.substring(0, 10) + "..." + str.substring(str.length - 10);
    }
    return str;
}

// Main execution
async function main() {
    console.log("=== B-Evoke FULL ECC Accumulator Proof Service ===");
    console.log("Using REAL elliptic curve operations on Baby Jubjub curve\n");

    const service = new FullECCAccumulatorProofService();

    // Check if circuit files exist
    if (!fs.existsSync(service.wasmPath)) {
        console.error("Error: ECC circuit WASM file not found. Please compile the circuit first.");
        process.exit(1);
    }
    if (!fs.existsSync(service.zkeyPath)) {
        console.error("Error: ECC circuit zkey file not found. Please run the trusted setup first.");
        process.exit(1);
    }

    console.log("Generating test inputs...");
    const { oldAccumulator, element, secret } = service.generateTestInputs();

    console.log("\nTest Configuration:");
    console.log("  Curve: Baby Jubjub (SNARK-friendly)");
    console.log("  Constraints: 1531 (vs 261 for hash-based)");
    console.log("  Operation: ACC_new = ACC_old + g^element");
    console.log("\nThis is REAL ECC, not hash-based!\n");

    console.log("Generating SNARK proof for ECC accumulator update...");
    const startTime = Date.now();

    const result = await service.generateECCAddProof(oldAccumulator, element, secret);

    const proofTime = Date.now() - startTime;
    console.log(`\nProof generated in ${proofTime}ms`);

    console.log("\nNew Accumulator Point:");
    console.log("  X:", truncate(result.newAccumulator.x));
    console.log("  Y:", truncate(result.newAccumulator.y));

    // Verify the proof locally
    console.log("\nVerifying proof locally...");
    const isValid = await service.verifyProof(result.proof, result.publicSignals);
    console.log("Proof is valid:", isValid);

    // Save proof to file
    const proofData = {
        proof: result.proof,
        publicSignals: result.publicSignals,
        oldAccumulator: {
            x: oldAccumulator.x.toString(),
            y: oldAccumulator.y.toString()
        },
        newAccumulator: result.newAccumulator,
        element: element.toString(),
        secret: secret.toString(),
        circuitType: "FULL_ECC_BABY_JUBJUB",
        constraints: 1531,
        timestamp: new Date().toISOString()
    };

    fs.writeFileSync("ecc-proof.json", JSON.stringify(proofData, null, 2));
    console.log("\nECC proof saved to ecc-proof.json");

    console.log("\n=== Key Difference from Hash-Based ===");
    console.log("Hash-based: newAcc = Hash(oldAcc, element, secret)");
    console.log("ECC-based:  newAcc = oldAcc + g^element (actual curve math!)");
    console.log("\nThis is what EVOKE paper actually requires!");

    return result;
}

// Export for use in other modules
module.exports = FullECCAccumulatorProofService;

// Run if called directly
if (require.main === module) {
    main()
        .then(() => {
            console.log("\nFull ECC proof generation successful!");
            process.exit(0);
        })
        .catch((err) => {
            console.error("Error:", err);
            process.exit(1);
        });
}