// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/B_Evoke_Registry_ECC.sol";
import "../src/ECCGroth16Verifier.sol";

/**
 * @title Comprehensive Test Suite for B-Evoke
 * @dev All tests for B-Evoke system including SNARK verification, edge cases, security, and performance
 */
contract B_Evoke_ExtendedTests is Test {
    B_Evoke_Registry_ECC public registry;
    Groth16Verifier public verifier;

    // Test accounts
    address owner = address(this);
    address device1 = address(0x1);
    address device2 = address(0x2);
    address device3 = address(0x3);
    address device4 = address(0x4);
    address device5 = address(0x5);
    address nonOwner = address(0x999);

    // Test constants
    uint256 constant MAX_UINT = type(uint256).max;
    uint256 constant FIELD_MODULUS = 21888242871839275222246405745257275088548364400416034343698204186575808495617;

    function setUp() public {
        verifier = new Groth16Verifier();
        registry = new B_Evoke_Registry_ECC();
    }

    // ============ SNARK Proof Verification Tests ============

    function testVerifyProof() public {
        // This proof was generated from ecc-proof.json
        uint[2] memory pA = [
            uint256(14368317894123461861060734365562020615765695903969464962275343882678522407144),
            uint256(14582127854420549026543986600127079096980298780540503682119167687237847327254)
        ];

        uint[2][2] memory pB = [
            [
                uint256(3537260192949750144809692717841284803853274648159234613837766712252344596858),
                uint256(1625684740296699267692870857255413035868029432191182295589649706897085550042)
            ],
            [
                uint256(12145204175769780602485131954388255164982851526213571587890321796374271118805),
                uint256(4204774910550531271887568106046280984302687932826992802669459025868730063445)
            ]
        ];

        uint[2] memory pC = [
            uint256(10167229318395833897285997461005048679211640929408589121181602661016380084706),
            uint256(2392398889868072395983584807362834356368406486883723751714348086112941490007)
        ];

        uint[2] memory pubSignals = [
            uint256(15792224776493125211988900681134708654687141103097577237352913688200059017865),
            uint256(6643075389408355939783418696373930583693564846944338325315042564834909547994)
        ];

        bool isValid = verifier.verifyProof(pA, pB, pC, pubSignals);
        assertTrue(isValid, "SNARK proof should be valid!");
    }

    function testInvalidProofFails() public {
        uint[2] memory pA = [uint256(1), uint256(2)];
        uint[2][2] memory pB = [[uint256(3), uint256(4)], [uint256(5), uint256(6)]];
        uint[2] memory pC = [uint256(7), uint256(8)];
        uint[2] memory pubSignals = [uint256(999), uint256(1)];

        bool isValid = verifier.verifyProof(pA, pB, pC, pubSignals);
        assertFalse(isValid, "Invalid proof should not verify");
    }

    function testProofWithWrongPublicSignal() public {
        uint[2] memory pA = [
            uint256(14368317894123461861060734365562020615765695903969464962275343882678522407144),
            uint256(14582127854420549026543986600127079096980298780540503682119167687237847327254)
        ];

        uint[2][2] memory pB = [
            [
                uint256(3537260192949750144809692717841284803853274648159234613837766712252344596858),
                uint256(1625684740296699267692870857255413035868029432191182295589649706897085550042)
            ],
            [
                uint256(12145204175769780602485131954388255164982851526213571587890321796374271118805),
                uint256(4204774910550531271887568106046280984302687932826992802669459025868730063445)
            ]
        ];

        uint[2] memory pC = [
            uint256(10167229318395833897285997461005048679211640929408589121181602661016380084706),
            uint256(2392398889868072395983584807362834356368406486883723751714348086112941490007)
        ];

        uint[2] memory pubSignals = [uint256(12345), uint256(67890)];

        bool isValid = verifier.verifyProof(pA, pB, pC, pubSignals);
        assertFalse(isValid, "Proof with wrong public signal should fail");
    }

    // ============ Registration Tests ============

    function testRegisterWithMaxDID() public {
        // Test with maximum bytes32 value
        bytes32 maxDid = bytes32(MAX_UINT);

        vm.prank(device1);
        registry.registerDevice(maxDid);

        B_Evoke_Registry_ECC.Device memory device = registry.getDevice(device1);
        assertEq(device.did, maxDid, "Should handle max bytes32 DID");
        assertTrue(device.isRegistered && !device.isRevoked, "Device should be valid");
    }

    function testDoubleRegistration() public {
        // Test registering same device twice
        bytes32 did = keccak256(abi.encodePacked("device1"));

        vm.prank(device1);
        registry.registerDevice(did);

        vm.prank(device1);
        vm.expectRevert("Device is already registered");
        registry.registerDevice(did);
    }

    function testRegisterEmptyDID() public {
        // Test with empty DID (should fail)
        bytes32 emptyDid = bytes32(0);

        vm.prank(device1);
        vm.expectRevert("Invalid DID");
        registry.registerDevice(emptyDid);
    }

    function testRegisterMultipleDevicesSequentially() public {
        // Register 10 devices sequentially
        for (uint i = 1; i <= 10; i++) {
            address deviceAddr = address(uint160(i));
            bytes32 did = keccak256(abi.encodePacked("device", i));

            vm.prank(deviceAddr);
            registry.registerDevice(did);

            assertTrue(registry.isDeviceValid(deviceAddr), "Device should be valid");
        }

        (uint256 total, uint256 valid, uint256 revoked,,,) = registry.getStatistics();
        assertEq(total, 10, "Should have 10 devices");
        assertEq(valid, 10, "All should be valid");
        assertEq(revoked, 0, "None should be revoked");
    }

    // ============ Revocation Tests ============

    function testRevokeUnregisteredDevice() public {
        // Try to revoke a device that was never registered
        vm.expectRevert("Device not found");
        registry.revokeDevice(device1);
    }

    function testRevokeAlreadyRevokedDevice() public {
        // Register and revoke a device
        bytes32 did = keccak256(abi.encodePacked("device1"));
        vm.prank(device1);
        registry.registerDevice(did);

        registry.revokeDevice(device1);

        // Try to revoke again
        vm.expectRevert("Device already revoked");
        registry.revokeDevice(device1);
    }

    function testNonOwnerCannotRevoke() public {
        // Register a device
        bytes32 did = keccak256(abi.encodePacked("device1"));
        vm.prank(device1);
        registry.registerDevice(did);

        // Non-owner tries to revoke
        vm.prank(nonOwner);
        vm.expectRevert();
        registry.revokeDevice(device1);
    }

    function testConsecutiveRevocations() public {
        // Register multiple devices
        for (uint i = 1; i <= 5; i++) {
            address deviceAddr = address(uint160(i));
            bytes32 did = keccak256(abi.encodePacked("device", i));
            vm.prank(deviceAddr);
            registry.registerDevice(did);
        }

        // Get initial accumulator
        (uint256 initialX, uint256 initialY) = registry.getAccumulator();

        // Revoke all devices consecutively
        for (uint i = 1; i <= 5; i++) {
            address deviceAddr = address(uint160(i));
            registry.revokeDevice(deviceAddr);
        }

        (uint256 finalX, uint256 finalY) = registry.getAccumulator();
        assertTrue(finalX != initialX || finalY != initialY, "Accumulator should change");

        (uint256 total, uint256 valid, uint256 revoked,,,) = registry.getStatistics();
        assertEq(revoked, 5, "Should have 5 revoked devices");
        assertEq(valid, 0, "No valid devices should remain");
    }

    function testBatchRevocationEmptyArray() public {
        // Test batch revoke with empty array
        address[] memory emptyBatch = new address[](0);
        registry.batchRevokeDevices(emptyBatch);

        // Should complete without reverting
        (uint256 total, uint256 valid, uint256 revoked,,,) = registry.getStatistics();
        assertEq(revoked, 0, "No devices should be revoked");
    }

    function testBatchRevocationSingleDevice() public {
        // Register a device
        bytes32 did = keccak256(abi.encodePacked("device1"));
        vm.prank(device1);
        registry.registerDevice(did);

        // Batch revoke single device
        address[] memory batch = new address[](1);
        batch[0] = device1;

        registry.batchRevokeDevices(batch);

        assertFalse(registry.isDeviceValid(device1), "Device should be revoked");
    }

    function testBatchRevocationLarge() public {
        // Register 50 devices
        for (uint i = 1; i <= 50; i++) {
            address deviceAddr = address(uint160(i));
            bytes32 did = keccak256(abi.encodePacked("device", i));
            vm.prank(deviceAddr);
            registry.registerDevice(did);
        }

        // Create batch array
        address[] memory batch = new address[](50);
        for (uint i = 0; i < 50; i++) {
            batch[i] = address(uint160(i + 1));
        }

        // Batch revoke all
        uint256 gasStart = gasleft();
        registry.batchRevokeDevices(batch);
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for 50 device batch revocation:", gasUsed);

        (uint256 total, uint256 valid, uint256 revoked,,,) = registry.getStatistics();
        assertEq(revoked, 50, "All 50 devices should be revoked");
        assertTrue(gasUsed < 5000000, "Gas should be reasonable");
    }

    function testBatchRevocationMixedValid() public {
        // Register only some devices
        vm.prank(device1);
        registry.registerDevice(keccak256(abi.encodePacked("device1")));
        vm.prank(device3);
        registry.registerDevice(keccak256(abi.encodePacked("device3")));

        // Try to batch revoke including unregistered device
        address[] memory batch = new address[](3);
        batch[0] = device1;
        batch[1] = device2; // Not registered
        batch[2] = device3;

        // Should handle gracefully
        registry.batchRevokeDevices(batch);

        // Check only registered devices were affected
        assertFalse(registry.isDeviceValid(device1), "Device1 should be revoked");
        assertFalse(registry.isDeviceValid(device3), "Device3 should be revoked");
    }

    // ============ Witness Update Tests ============

    function testUpdateWitnessAsNonDevice() public {
        // Try to update witness without being registered
        vm.prank(nonOwner);
        vm.expectRevert("Device is not registered");
        registry.updateDeviceWitness(12345, 67890);
    }

    function testUpdateWitnessAsRevokedDevice() public {
        // Register and revoke a device
        bytes32 did = keccak256(abi.encodePacked("device1"));
        vm.prank(device1);
        registry.registerDevice(did);
        registry.revokeDevice(device1);

        // Try to update witness as revoked device
        vm.prank(device1);
        vm.expectRevert("Cannot update witness for revoked device");
        registry.updateDeviceWitness(12345, 67890);
    }

    function testValidWitnessUpdate() public {
        // Register a device
        bytes32 did = keccak256(abi.encodePacked("device1"));
        vm.prank(device1);
        registry.registerDevice(did);

        // Update witness
        uint256 witnessX = 5299619240641551281634865583518297030282874472190772894086521144482721001553;
        uint256 witnessY = 16950150798460657717958625567821834550301663161624707787222815936182638968203;

        vm.prank(device1);
        registry.updateDeviceWitness(witnessX, witnessY);

        B_Evoke_Registry_ECC.Device memory device = registry.getDevice(device1);
        assertEq(device.witness.x, witnessX, "Witness X should be updated");
        assertEq(device.witness.y, witnessY, "Witness Y should be updated");
    }

    function testMultipleWitnessUpdates() public {
        // Register a device
        bytes32 did = keccak256(abi.encodePacked("device1"));
        vm.prank(device1);
        registry.registerDevice(did);

        // Update witness multiple times
        for (uint i = 1; i <= 5; i++) {
            vm.prank(device1);
            registry.updateDeviceWitness(i * 1000, i * 2000);

            B_Evoke_Registry_ECC.Device memory device = registry.getDevice(device1);
            assertEq(device.witness.x, i * 1000, "Witness X should update");
            assertEq(device.witness.y, i * 2000, "Witness Y should update");
        }
    }

    // ============ Membership Verification Tests ============

    function testVerifyMembershipWithoutRevocation() public {
        // Register a device but don't revoke it
        vm.prank(device1);
        registry.registerDevice(keccak256(abi.encodePacked("device1")));

        // Try to verify membership (should fail since not revoked)
        vm.expectRevert("Device not revoked");
        registry.verifyMembershipProof(device1, 12345, 67890);
    }

    function testVerifyMembershipWithInvalidWitness() public {
        // Register and revoke a device
        vm.prank(device1);
        registry.registerDevice(keccak256(abi.encodePacked("device1")));
        registry.revokeDevice(device1);

        // Try to verify with incorrect witness values
        bool isValid = registry.verifyMembershipProof(device1, 0, 0);
        assertFalse(isValid, "Invalid witness should not verify");
    }

    function testVerifyMembershipNonExistentDevice() public {
        // Try to verify membership for non-existent device
        vm.expectRevert("Device not revoked");
        registry.verifyMembershipProof(device1, 12345, 67890);
    }

    // ============ Gas Optimization Tests ============

    function testRegistrationGasCost() public {
        uint256 gasStart = gasleft();

        vm.prank(device1);
        registry.registerDevice(keccak256(abi.encodePacked("gas_test")));

        uint256 gasUsed = gasStart - gasleft();
        console.log("Gas used for device registration:", gasUsed);
        assertTrue(gasUsed < 200000, "Registration should use less than 200k gas");
    }

    function testRevocationGasCost() public {
        // Register device first
        vm.prank(device1);
        registry.registerDevice(keccak256(abi.encodePacked("gas_test")));

        uint256 gasStart = gasleft();
        registry.revokeDevice(device1);
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for device revocation:", gasUsed);
        assertTrue(gasUsed < 150000, "Revocation should use less than 150k gas");
    }

    function testMembershipVerificationGasCost() public {
        // Register a device
        vm.prank(device1);
        registry.registerDevice(keccak256(abi.encodePacked("device1")));

        // Update witness with valid values before revocation
        uint256 witnessX = 5299619240641551281634865583518297030282874472190772894086521144482721001553;
        uint256 witnessY = 16950150798460657717958625567821834550301663161624707787222815936182638968203;

        vm.prank(device1);
        registry.updateDeviceWitness(witnessX, witnessY);

        // Now revoke the device
        registry.revokeDevice(device1);

        // Test gas cost of membership verification
        uint256 gasStart = gasleft();
        registry.verifyMembershipProof(device1, witnessX, witnessY);
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for membership verification:", gasUsed);
        assertTrue(gasUsed < 100000, "Membership verification should use less than 100k gas");
    }

    // ============ State Consistency Tests ============

    function testAccumulatorConsistency() public {
        // Register and revoke devices, checking accumulator changes
        (uint256 startX, uint256 startY) = registry.getAccumulator();

        // Register device1
        vm.prank(device1);
        registry.registerDevice(keccak256(abi.encodePacked("device1")));

        (uint256 afterRegX, uint256 afterRegY) = registry.getAccumulator();
        assertEq(startX, afterRegX, "Accumulator shouldn't change on registration");
        assertEq(startY, afterRegY, "Accumulator shouldn't change on registration");

        // Revoke device1
        registry.revokeDevice(device1);

        (uint256 afterRevX, uint256 afterRevY) = registry.getAccumulator();
        assertTrue(afterRevX != startX || afterRevY != startY, "Accumulator should change on revocation");
    }

    function testStatisticsAccuracy() public {
        // Register 10 devices
        for (uint i = 1; i <= 10; i++) {
            address deviceAddr = address(uint160(i));
            vm.prank(deviceAddr);
            registry.registerDevice(keccak256(abi.encodePacked("device", i)));
        }

        // Revoke 5 devices
        for (uint i = 1; i <= 5; i++) {
            registry.revokeDevice(address(uint160(i)));
        }

        (uint256 total, uint256 valid, uint256 revoked,,,) = registry.getStatistics();
        assertEq(total, 10, "Should have 10 total devices");
        assertEq(valid, 5, "Should have 5 valid devices");
        assertEq(revoked, 5, "Should have 5 revoked devices");
    }

    // ============ Additional Edge Cases ============

    function testZeroAddressOperations() public {
        // Test that zero address can register (no restriction in contract)
        vm.prank(address(0));
        registry.registerDevice(keccak256(abi.encodePacked("zero_device")));

        // Verify it registered successfully
        B_Evoke_Registry_ECC.Device memory device = registry.getDevice(address(0));
        assertTrue(device.isRegistered, "Zero address should be able to register");
    }

    function testMaxBatchSize() public {
        // Test with maximum reasonable batch size
        uint256 batchSize = 100;

        // Register devices
        for (uint i = 1; i <= batchSize; i++) {
            address deviceAddr = address(uint160(i));
            vm.prank(deviceAddr);
            registry.registerDevice(keccak256(abi.encodePacked("device", i)));
        }

        // Create batch array
        address[] memory batch = new address[](batchSize);
        for (uint i = 0; i < batchSize; i++) {
            batch[i] = address(uint160(i + 1));
        }

        // Batch revoke
        registry.batchRevokeDevices(batch);

        (uint256 total, uint256 valid, uint256 revoked,,,) = registry.getStatistics();
        assertEq(revoked, batchSize, "All devices should be revoked");
    }
}