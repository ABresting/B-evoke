// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/B_Evoke_Registry.sol";

contract B_Evoke_RegistryTest is Test {
    B_Evoke_Registry public registry;

    // Test accounts
    address owner = address(this);
    address device1 = address(0x1);
    address device2 = address(0x2);
    address device3 = address(0x3);
    address device4 = address(0x4);
    address unauthorized = address(0x5);

    // Test data
    bytes32 constant TEST_DID_1 = keccak256("did:evoke:device1");
    bytes32 constant TEST_DID_2 = keccak256("did:evoke:device2");
    bytes32 constant TEST_DID_3 = keccak256("did:evoke:device3");
    bytes32 constant TEST_DID_4 = keccak256("did:evoke:device4");
    string constant TEST_PUBLIC_KEY = "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA";
    bytes32 constant TEST_WITNESS = keccak256("witness:data:001");

    // Events to test
    event DeviceRegistered(address indexed deviceAddress, bytes32 indexed did, uint256 timestamp);
    event DeviceRevoked(address indexed deviceAddress, uint256 timestamp);
    event DeviceReinstated(address indexed deviceAddress, uint256 timestamp);
    event AccumulatorUpdated(bytes32 newAccumulator, uint256 updateCount);
    event WitnessUpdated(address indexed deviceAddress, bytes32 newWitness);
    event MassRevocation(address[] devices, uint256 timestamp);

    function setUp() public {
        registry = new B_Evoke_Registry();
    }

    // ============ Device Registration Tests ============

    function testRegisterDevice() public {
        vm.startPrank(device1);

        // Register device (with empty credential hash for now)
        registry.registerDevice(TEST_PUBLIC_KEY, TEST_DID_1, "");

        // Verify registration
        B_Evoke_Registry.Device memory device = registry.getDevice(device1);
        assertEq(device.isRegistered, true);
        assertEq(device.isRevoked, false);
        assertEq(device.did, TEST_DID_1);
        assertEq(device.publicKey, TEST_PUBLIC_KEY);
        assertEq(device.deviceAddress, device1);

        // Check witness was generated
        bytes32 witness = registry.getDeviceWitness(device1);
        assertTrue(witness != bytes32(0));

        vm.stopPrank();
    }

    function testRegisterDeviceWithCredentialHash() public {
        vm.startPrank(device1);

        string memory credentialHash = "QmTzQ1NfQYGKZHZfFHcWZmC6BsKmyKHJFtCnGYGNvGFMRw";

        // Register device with credential hash
        registry.registerDevice(TEST_PUBLIC_KEY, TEST_DID_1, credentialHash);

        // Verify credential hash was stored
        assertEq(registry.deviceCredentialHash(device1), credentialHash);

        vm.stopPrank();
    }

    function testCannotRegisterDuplicateDevice() public {
        vm.startPrank(device1);

        registry.registerDevice(TEST_PUBLIC_KEY, TEST_DID_1, "");

        // Try to register again
        vm.expectRevert("Device is already registered");
        registry.registerDevice(TEST_PUBLIC_KEY, TEST_DID_1, "");

        vm.stopPrank();
    }

    function testCannotRegisterWithInvalidDID() public {
        vm.startPrank(device1);

        vm.expectRevert("Invalid DID");
        registry.registerDevice(TEST_PUBLIC_KEY, bytes32(0), "");

        vm.stopPrank();
    }

    function testDeviceStatisticsAfterRegistration() public {
        // Register multiple devices
        vm.prank(device1);
        registry.registerDevice(TEST_PUBLIC_KEY, TEST_DID_1, "");

        vm.prank(device2);
        registry.registerDevice(TEST_PUBLIC_KEY, TEST_DID_2, "");

        // Check statistics
        (uint256 totalDevices, uint256 activeDevices, uint256 revokedDevices,) = registry.getStatistics();
        assertEq(totalDevices, 2);
        assertEq(activeDevices, 2);
        assertEq(revokedDevices, 0);
    }

    function testGlobalAccumulatorInitialized() public {
        // Check that global accumulator is initialized
        bytes32 accumulator = registry.globalAccumulator();
        assertTrue(accumulator != bytes32(0));
        assertEq(registry.accumulatorUpdateCount(), 1);
    }

    // ============ Device Revocation Tests ============

    function testRevokeDevice() public {
        // Register device
        vm.prank(device1);
        registry.registerDevice(TEST_PUBLIC_KEY, TEST_DID_1, "");

        // Get initial accumulator
        bytes32 initialAccumulator = registry.globalAccumulator();

        // Revoke device (as owner)
        registry.revokeDevice(device1);

        // Verify revocation
        B_Evoke_Registry.Device memory device = registry.getDevice(device1);
        assertEq(device.isRevoked, true);

        // Check statistics
        (,uint256 activeDevices, uint256 revokedDevices,) = registry.getStatistics();
        assertEq(activeDevices, 0);
        assertEq(revokedDevices, 1);

        // Verify accumulator was updated
        bytes32 newAccumulator = registry.globalAccumulator();
        assertTrue(newAccumulator != initialAccumulator);
        assertEq(registry.accumulatorUpdateCount(), 2);
    }

    function testCannotRevokeUnregisteredDevice() public {
        vm.expectRevert("Device not found");
        registry.revokeDevice(device1);
    }

    function testCannotRevokeAlreadyRevokedDevice() public {
        // Register and revoke device
        vm.prank(device1);
        registry.registerDevice(TEST_PUBLIC_KEY, TEST_DID_1, "");
        registry.revokeDevice(device1);

        // Try to revoke again
        vm.expectRevert("Device already revoked");
        registry.revokeDevice(device1);
    }

    function testReinstateDevice() public {
        // Register and revoke device
        vm.prank(device1);
        registry.registerDevice(TEST_PUBLIC_KEY, TEST_DID_1, "");
        registry.revokeDevice(device1);

        // Reinstate device
        registry.reinstateDevice(device1);

        // Verify reinstatement
        B_Evoke_Registry.Device memory device = registry.getDevice(device1);
        assertEq(device.isRevoked, false);

        // Check statistics
        (,uint256 activeDevices, uint256 revokedDevices,) = registry.getStatistics();
        assertEq(activeDevices, 1);
        assertEq(revokedDevices, 0);
    }

    function testMassRevocation() public {
        // Register multiple devices
        vm.prank(device1);
        registry.registerDevice(TEST_PUBLIC_KEY, TEST_DID_1, "");

        vm.prank(device2);
        registry.registerDevice(TEST_PUBLIC_KEY, TEST_DID_2, "");

        vm.prank(device3);
        registry.registerDevice(TEST_PUBLIC_KEY, TEST_DID_3, "");

        // Get initial accumulator update count
        uint256 initialUpdateCount = registry.accumulatorUpdateCount();

        // Mass revocation
        address[] memory devicesToRevoke = new address[](3);
        devicesToRevoke[0] = device1;
        devicesToRevoke[1] = device2;
        devicesToRevoke[2] = device3;

        registry.massRevokeDevices(devicesToRevoke);

        // Check all devices are revoked
        assertTrue(registry.getDevice(device1).isRevoked);
        assertTrue(registry.getDevice(device2).isRevoked);
        assertTrue(registry.getDevice(device3).isRevoked);

        // Check statistics
        (,uint256 activeDevices, uint256 revokedDevices,) = registry.getStatistics();
        assertEq(activeDevices, 0);
        assertEq(revokedDevices, 3);

        // Verify only one accumulator update for mass revocation
        assertEq(registry.accumulatorUpdateCount(), initialUpdateCount + 1);
    }

    function testRevocationEvent() public {
        vm.prank(device1);
        registry.registerDevice(TEST_PUBLIC_KEY, TEST_DID_1, "");

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit DeviceRevoked(device1, block.timestamp);

        registry.revokeDevice(device1);
    }

    function testMassRevocationEvent() public {
        // Register devices
        vm.prank(device1);
        registry.registerDevice(TEST_PUBLIC_KEY, TEST_DID_1, "");
        vm.prank(device2);
        registry.registerDevice(TEST_PUBLIC_KEY, TEST_DID_2, "");

        address[] memory devicesToRevoke = new address[](2);
        devicesToRevoke[0] = device1;
        devicesToRevoke[1] = device2;

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit MassRevocation(devicesToRevoke, block.timestamp);

        registry.massRevokeDevices(devicesToRevoke);
    }

    // ============ Witness Management Tests ============

    function testUpdateDeviceWitness() public {
        vm.prank(device1);
        registry.registerDevice(TEST_PUBLIC_KEY, TEST_DID_1, "");

        bytes32 newWitness = keccak256("new:witness:data");

        vm.prank(device1);
        registry.updateDeviceWitness(newWitness);

        assertEq(registry.getDeviceWitness(device1), newWitness);
    }

    function testRevokedDeviceCannotUpdateWitness() public {
        // Register and revoke device
        vm.prank(device1);
        registry.registerDevice(TEST_PUBLIC_KEY, TEST_DID_1, "");
        registry.revokeDevice(device1);

        // Try to update witness
        vm.prank(device1);
        vm.expectRevert("Device credentials are revoked");
        registry.updateDeviceWitness(TEST_WITNESS);
    }

    function testBatchUpdateWitnesses() public {
        // Register multiple devices
        vm.prank(device1);
        registry.registerDevice(TEST_PUBLIC_KEY, TEST_DID_1, "");
        vm.prank(device2);
        registry.registerDevice(TEST_PUBLIC_KEY, TEST_DID_2, "");
        vm.prank(device3);
        registry.registerDevice(TEST_PUBLIC_KEY, TEST_DID_3, "");

        // Prepare batch update
        address[] memory devices = new address[](3);
        devices[0] = device1;
        devices[1] = device2;
        devices[2] = device3;

        bytes32[] memory witnesses = new bytes32[](3);
        witnesses[0] = keccak256("witness1");
        witnesses[1] = keccak256("witness2");
        witnesses[2] = keccak256("witness3");

        // Batch update
        registry.batchUpdateWitnesses(devices, witnesses);

        // Verify updates
        assertEq(registry.getDeviceWitness(device1), witnesses[0]);
        assertEq(registry.getDeviceWitness(device2), witnesses[1]);
        assertEq(registry.getDeviceWitness(device3), witnesses[2]);
    }

    function testBatchUpdateSkipsRevokedDevices() public {
        // Register devices
        vm.prank(device1);
        registry.registerDevice(TEST_PUBLIC_KEY, TEST_DID_1, "");
        vm.prank(device2);
        registry.registerDevice(TEST_PUBLIC_KEY, TEST_DID_2, "");

        // Revoke device1
        registry.revokeDevice(device1);

        // Get initial witness for device1
        bytes32 initialWitness = registry.getDeviceWitness(device1);

        // Batch update including revoked device
        address[] memory devices = new address[](2);
        devices[0] = device1;
        devices[1] = device2;

        bytes32[] memory witnesses = new bytes32[](2);
        witnesses[0] = keccak256("should_not_update");
        witnesses[1] = keccak256("should_update");

        registry.batchUpdateWitnesses(devices, witnesses);

        // Device1 witness should not change (revoked)
        assertEq(registry.getDeviceWitness(device1), initialWitness);
        // Device2 witness should update
        assertEq(registry.getDeviceWitness(device2), witnesses[1]);
    }

    function testWitnessUpdatedEvent() public {
        vm.prank(device1);
        registry.registerDevice(TEST_PUBLIC_KEY, TEST_DID_1, "");

        bytes32 newWitness = keccak256("new:witness");

        vm.prank(device1);
        vm.expectEmit(true, true, true, true);
        emit WitnessUpdated(device1, newWitness);

        registry.updateDeviceWitness(newWitness);
    }

    // ============ Access Control Tests ============

    function testOnlyOwnerCanRevokeDevices() public {
        vm.prank(device1);
        registry.registerDevice(TEST_PUBLIC_KEY, TEST_DID_1, "");

        vm.prank(unauthorized);
        vm.expectRevert("Only owner can perform this action");
        registry.revokeDevice(device1);
    }

    function testOnlyOwnerCanBatchUpdateWitnesses() public {
        address[] memory devices = new address[](1);
        devices[0] = device1;

        bytes32[] memory witnesses = new bytes32[](1);
        witnesses[0] = TEST_WITNESS;

        vm.prank(unauthorized);
        vm.expectRevert("Only owner can perform this action");
        registry.batchUpdateWitnesses(devices, witnesses);
    }

    // ============ View Functions Tests ============

    function testIsDeviceValid() public {
        vm.prank(device1);
        registry.registerDevice(TEST_PUBLIC_KEY, TEST_DID_1, "");

        // Valid device
        assertEq(registry.isDeviceValid(device1), true);

        // Revoke device
        registry.revokeDevice(device1);
        assertEq(registry.isDeviceValid(device1), false);

        // Non-existent device
        assertEq(registry.isDeviceValid(device2), false);
    }

    function testGetStatistics() public {
        // Register devices
        vm.prank(device1);
        registry.registerDevice(TEST_PUBLIC_KEY, TEST_DID_1, "");
        vm.prank(device2);
        registry.registerDevice(TEST_PUBLIC_KEY, TEST_DID_2, "");

        // Revoke one device
        registry.revokeDevice(device1);

        (uint256 totalDevices, uint256 activeDevices, uint256 revokedDevices, uint256 accumulatorUpdates) = registry.getStatistics();
        assertEq(totalDevices, 2);
        assertEq(activeDevices, 1);
        assertEq(revokedDevices, 1);
        assertEq(accumulatorUpdates, 2); // 1 initial + 1 revocation
    }

    // ============ Fuzz Testing ============

    function testFuzz_RegisterDevice(string memory publicKey, bytes32 did) public {
        vm.assume(did != bytes32(0)); // DID must not be zero

        address device = address(uint160(uint256(did))); // Generate address from DID
        vm.assume(device != address(0));

        vm.prank(device);
        registry.registerDevice(publicKey, did, "");

        B_Evoke_Registry.Device memory registeredDevice = registry.getDevice(device);
        assertEq(registeredDevice.did, did);
        assertEq(registeredDevice.publicKey, publicKey);
    }

    function testFuzz_MassRevocation(uint8 deviceCount) public {
        vm.assume(deviceCount > 0 && deviceCount <= 10); // Limit for gas efficiency

        address[] memory devices = new address[](deviceCount);

        // Register devices
        for (uint i = 0; i < deviceCount; i++) {
            address deviceAddr = address(uint160(100 + i));
            devices[i] = deviceAddr;

            vm.prank(deviceAddr);
            registry.registerDevice(TEST_PUBLIC_KEY, keccak256(abi.encodePacked("did", i)), "");
        }

        // Mass revoke
        registry.massRevokeDevices(devices);

        // Verify all revoked
        for (uint i = 0; i < deviceCount; i++) {
            assertTrue(registry.getDevice(devices[i]).isRevoked);
        }

        // Check statistics
        (,uint256 activeDevices, uint256 revokedDevices,) = registry.getStatistics();
        assertEq(activeDevices, 0);
        assertEq(revokedDevices, deviceCount);
    }
}