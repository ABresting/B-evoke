pragma circom 2.0.0;

include "circomlib/circuits/babyjub.circom";
include "circomlib/circuits/escalarmulany.circom";
include "circomlib/circuits/bitify.circom";
include "circomlib/circuits/comparators.circom";

/*
 * EVOKE Membership Witness Circuit - Simplified Version
 *
 * Proves that an element IS in the accumulator
 * For revocation: Proves a device credential has been revoked
 *
 * Equation: A = W + g^element
 * Where:
 *   A = current accumulator (public)
 *   element = device credential (private)
 *   W = witness (private)
 *   g = generator point
 */
template EVOKEMembership() {
    // Public inputs
    signal input accX;           // Current accumulator X (public)
    signal input accY;           // Current accumulator Y (public)

    // Private inputs
    signal input element;        // Element to prove membership (device ID)
    signal input witnessX;       // Witness point X coordinate
    signal input witnessY;       // Witness point Y coordinate

    // Baby Jubjub base point
    var BASE8[2] = [
        5299619240641551281634865583518297030282874472190772894086521144482721001553,
        16950150798460657717958625567821834550301663161624707787222815936182638968203
    ];

    // Step 1: Compute g^element
    component elementPoint = EscalarMulAny(254);
    elementPoint.p[0] <== BASE8[0];
    elementPoint.p[1] <== BASE8[1];

    component n2b = Num2Bits(254);
    n2b.in <== element;

    for (var i = 0; i < 254; i++) {
        elementPoint.e[i] <== n2b.out[i];
    }

    // Step 2: Add witness + g^element
    // Should equal accumulator if element is member
    component pointAdd = BabyAdd();
    pointAdd.x1 <== witnessX;
    pointAdd.y1 <== witnessY;
    pointAdd.x2 <== elementPoint.out[0];
    pointAdd.y2 <== elementPoint.out[1];

    // Step 3: Enforce equality with accumulator
    // This will fail if element is not in accumulator
    accX === pointAdd.xout;
    accY === pointAdd.yout;
}

component main = EVOKEMembership();