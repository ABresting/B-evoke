pragma circom 2.0.0;

include "circomlib/circuits/babyjub.circom";
include "circomlib/circuits/escalarmulany.circom";
include "circomlib/circuits/bitify.circom";

/*
 * Full ECC-based Accumulator using Baby Jubjub Curve
 *
 * This implements a REAL elliptic curve accumulator where:
 * - Accumulator is a point on Baby Jubjub curve (x,y coordinates)
 * - Adding element: ACC_new = ACC_old + g^element (point addition)
 * - Uses actual elliptic curve mathematics, not hashes
 *
 * Key difference from hash-based:
 * - Hash: newAcc = Hash(oldAcc, element, secret)
 * - ECC: newAcc = oldAcc + g^element (actual curve point operations)
 */

template ECCAccumulator() {
    // Private inputs
    signal input oldAccX;        // Old accumulator X coordinate
    signal input oldAccY;        // Old accumulator Y coordinate
    signal input element;        // Element to add (scalar)
    signal input secret;         // Additional randomness

    // Public outputs
    signal output newAccX;       // New accumulator X coordinate
    signal output newAccY;       // New accumulator Y coordinate

    // Baby Jubjub base point (generator)
    var BASE8[2] = [
        5299619240641551281634865583518297030282874472190772894086521144482721001553,
        16950150798460657717958625567821834550301663161624707787222815936182638968203
    ];

    // Combine element with secret for added security
    signal combined;
    combined <== element * secret + element + secret;

    // Scalar multiplication: g^combined
    // This computes point = g * combined on Baby Jubjub curve
    component scalarMul = EscalarMulAny(254);
    scalarMul.p[0] <== BASE8[0];
    scalarMul.p[1] <== BASE8[1];

    // Convert combined to bits for scalar multiplication
    component n2b = Num2Bits(254);
    n2b.in <== combined;

    for (var i = 0; i < 254; i++) {
        scalarMul.e[i] <== n2b.out[i];
    }

    // Point addition: ACC_new = ACC_old + g^combined
    // This is actual elliptic curve point addition
    component pointAdd = BabyAdd();
    pointAdd.x1 <== oldAccX;
    pointAdd.y1 <== oldAccY;
    pointAdd.x2 <== scalarMul.out[0];
    pointAdd.y2 <== scalarMul.out[1];

    // Output the new accumulator point
    newAccX <== pointAdd.xout;
    newAccY <== pointAdd.yout;
}

// Main component for ECC accumulator
component main = ECCAccumulator();