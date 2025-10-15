#!/bin/bash

# ═══════════════════════════════════════════════════════════════════════
#                      B-EVOKE SYSTEM VERIFICATION
# ═══════════════════════════════════════════════════════════════════════
#
# WHAT THIS FILE DOES:
# Quick health check to verify the B-Evoke system is ready to run.
# This checks that all required files exist and circuits are compiled.
#
# WHAT IT CHECKS:
# 1. You're in the correct directory
# 2. Core circuit files exist (ecc_accumulator.circom, evoke_membership_simple.circom)
# 3. Service files exist (test-evoke.js)
# 4. Smart contracts exist (B_Evoke_Registry_ECC.sol)
# 5. Circuits are compiled (*.r1cs files)
# 6. Documentation is present
#
# HOW TO RUN:
# ./verify.sh
# or: bash verify.sh
#
# EXPECTED OUTPUT:
# - Green checkmarks (✅) for all checks if system is ready
# - Quick command reference for what to run next
# - Takes ~5 seconds to complete
#
# WHAT SUCCESS LOOKS LIKE:
# All files found, circuits compiled, system ready message displayed.
#
# ═══════════════════════════════════════════════════════════════════════

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║            B-EVOKE SYSTEM VERIFICATION                       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Check if we're in the right directory
if [ ! -f "test-evoke.js" ]; then
    echo "❌ Error: Not in b-evoke directory"
    echo "   Please cd to the project directory first"
    echo ""
    exit 1
fi

echo "📁 Project Directory: $(pwd)"
echo ""

# Track if all checks pass
all_checks_passed=true

echo "┌──────────────────────────────────────────────────────────────┐"
echo "│ CHECKING CORE FILES                                          │"
echo "└──────────────────────────────────────────────────────────────┘"
echo ""

# Check circuits
if [ -f "circuits/ecc_accumulator.circom" ]; then
    echo "✅ ECC accumulator circuit found"
else
    echo "❌ ECC accumulator circuit missing"
    all_checks_passed=false
fi

if [ -f "circuits/evoke_membership_simple.circom" ]; then
    echo "✅ Membership circuit found"
else
    echo "❌ Membership circuit missing"
    all_checks_passed=false
fi

# Check test file
if [ -f "test-evoke.js" ]; then
    echo "✅ Test suite found (test-evoke.js)"
else
    echo "❌ Test suite missing"
    all_checks_passed=false
fi

# Check smart contracts
if [ -f "src/B_Evoke_Registry_ECC.sol" ]; then
    echo "✅ ECC smart contract found"
else
    echo "❌ ECC smart contract missing"
    all_checks_passed=false
fi

if [ -f "src/ECCGroth16Verifier.sol" ]; then
    echo "✅ SNARK verifier contract found"
else
    echo "❌ SNARK verifier contract missing"
    all_checks_passed=false
fi

echo ""
echo "┌──────────────────────────────────────────────────────────────┐"
echo "│ CHECKING COMPILED CIRCUITS                                   │"
echo "└──────────────────────────────────────────────────────────────┘"
echo ""

# Check if circuits are compiled
circuits_compiled=true

if [ -f "circuits/ecc/ecc_accumulator.r1cs" ]; then
    echo "✅ ECC circuit compiled"
    # Show constraint count
    constraint_count=$(npx snarkjs r1cs info circuits/ecc/ecc_accumulator.r1cs 2>/dev/null | grep "# of Constraints" | awk '{print $NF}')
    if [ -n "$constraint_count" ]; then
        echo "   Constraints: $constraint_count"
    fi
else
    echo "⚠️  ECC circuit not compiled"
    circuits_compiled=false
fi

if [ -f "circuits/evoke/evoke_membership_simple.r1cs" ]; then
    echo "✅ Membership circuit compiled"
    # Show constraint count
    constraint_count=$(npx snarkjs r1cs info circuits/evoke/evoke_membership_simple.r1cs 2>/dev/null | grep "# of Constraints" | awk '{print $NF}')
    if [ -n "$constraint_count" ]; then
        echo "   Constraints: $constraint_count"
    fi
else
    echo "⚠️  Membership circuit not compiled"
    circuits_compiled=false
fi

echo ""
echo "┌──────────────────────────────────────────────────────────────┐"
echo "│ DOCUMENTATION                                                │"
echo "└──────────────────────────────────────────────────────────────┘"
echo ""

doc_count=0
for doc in README.md TECHNICAL_EXPLANATION.md EVOKE_IMPLEMENTATION_COMPLETE.md CONTEXT_SUMMARY.md; do
    if [ -f "$doc" ]; then
        ((doc_count++))
    fi
done

echo "✅ $doc_count documentation files found"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                      VERIFICATION RESULT                     ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

if $all_checks_passed && $circuits_compiled; then
    echo "✅ ALL CHECKS PASSED - System Ready!"
    echo ""
    echo "🚀 Quick Start:"
    echo "───────────────"
    echo ""
    echo "  Run comprehensive tests:"
    echo "  → node test-evoke.js"
    echo ""
    echo "  Compile smart contracts:"
    echo "  → forge build --via-ir"
    echo ""
    echo "  Run contract tests:"
    echo "  → forge test --via-ir"
    echo ""
    echo "📚 Documentation:"
    echo "─────────────────"
    echo "  • README.md                       - Quick start guide"
    echo "  • TECHNICAL_EXPLANATION.md        - How it works"
    echo "  • EVOKE_IMPLEMENTATION_COMPLETE.md - Full technical details"
    echo "  • CONTEXT_SUMMARY.md              - Project context"
    echo ""
elif $all_checks_passed; then
    echo "⚠️  CORE FILES OK - Circuits need compilation"
    echo ""
    echo "To compile circuits, follow the setup in README.md"
    echo ""
elif ! $all_checks_passed; then
    echo "❌ SOME FILES MISSING"
    echo ""
    echo "Missing files detected. Please check the installation."
    echo ""
fi

echo "═══════════════════════════════════════════════════════════════"
echo " B-Evoke: EVOKE implementation with real ECC on Baby Jubjub"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Exit with appropriate code
if $all_checks_passed; then
    exit 0
else
    exit 1
fi
