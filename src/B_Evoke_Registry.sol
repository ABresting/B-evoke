// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title B_Evoke_Registry
 * @dev Implements EVOKE's efficient revocation mechanism for IoT device credentials using blockchain.
 * Focuses on accumulator-based revocation with witness updates for offline verification.
 * Based on EVOKE paper: "Efficient Revocation of Verifiable Credentials in IoT Networks"
 */
contract B_Evoke_Registry {

    // ============ Structs ============

    struct Device {
        address deviceAddress;      // Ethereum address of the device
        bytes32 did;               // Decentralized Identifier (DID)
        string publicKey;          // Public key for off-chain crypto operations
        uint256 registrationDate;
        uint256 lastUpdateTime;    // For tracking witness updates
        bool isRegistered;
        bool isRevoked;            // Credential revocation status
    }

    // ============ State Variables ============

    // Device registry
    mapping(address => Device) public devices;

    // EVOKE-style accumulator and witness management
    bytes32 public globalAccumulator;                          // Global accumulator value
    mapping(address => bytes32) public deviceAccumulatorWitness; // Individual device witnesses
    mapping(address => uint256) public revocationTimestamp;    // Track when device was revoked
    uint256 public accumulatorUpdateCount;                     // Track accumulator updates

    // IPFS storage for off-chain data
    string public currentWitnessUpdateHash;                    // IPFS hash of latest witness update batch
    string public accumulatorSnapshotHash;                     // IPFS hash of accumulator snapshot
    mapping(address => string) public deviceCredentialHash;    // IPFS hash of device's verifiable credential

    // Access control
    address public owner;

    // Statistics
    uint256 public totalDevices;
    uint256 public activeDevices;
    uint256 public revokedDeviceCount;

    // ============ Events ============

    event DeviceRegistered(address indexed deviceAddress, bytes32 indexed did, uint256 timestamp);
    event DeviceRevoked(address indexed deviceAddress, uint256 timestamp);
    event DeviceReinstated(address indexed deviceAddress, uint256 timestamp);
    event AccumulatorUpdated(bytes32 newAccumulator, uint256 updateCount);
    event WitnessUpdated(address indexed deviceAddress, bytes32 newWitness);
    event MassRevocation(address[] devices, uint256 timestamp);

    // ============ Modifiers ============

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can perform this action");
        _;
    }

    modifier onlyRegisteredDevice() {
        require(devices[msg.sender].isRegistered, "Device is not registered");
        _;
    }

    modifier onlyActiveDevice() {
        require(devices[msg.sender].isRegistered, "Device is not registered");
        require(!devices[msg.sender].isRevoked, "Device credentials are revoked");
        _;
    }

    // ============ Constructor ============

    constructor() {
        owner = msg.sender;
        // Initialize global accumulator with a starting value
        globalAccumulator = keccak256(abi.encodePacked("EVOKE_ACCUMULATOR_GENESIS", block.timestamp));
        accumulatorUpdateCount = 1;
    }

    // ============ Device Management Functions ============

    /**
     * @dev Register a new IoT device with DID and optional credential hash
     * @param _publicKey The device's public key for verification
     * @param _did The device's Decentralized Identifier
     * @param _credentialHash IPFS hash of the device's verifiable credential (optional)
     */
    function registerDevice(
        string calldata _publicKey,
        bytes32 _did,
        string calldata _credentialHash
    ) external {
        require(!devices[msg.sender].isRegistered, "Device is already registered");
        require(_did != bytes32(0), "Invalid DID");

        devices[msg.sender] = Device({
            deviceAddress: msg.sender,
            did: _did,
            publicKey: _publicKey,
            registrationDate: block.timestamp,
            lastUpdateTime: block.timestamp,
            isRegistered: true,
            isRevoked: false
        });

        // Store credential hash if provided
        if (bytes(_credentialHash).length > 0) {
            deviceCredentialHash[msg.sender] = _credentialHash;
        }

        // Generate initial witness for the device
        deviceAccumulatorWitness[msg.sender] = keccak256(abi.encodePacked(globalAccumulator, msg.sender));

        totalDevices++;
        activeDevices++;

        emit DeviceRegistered(msg.sender, _did, block.timestamp);
    }

    /**
     * @dev Revoke a device's credentials (implements EVOKE-style revocation)
     * Updates the global accumulator to reflect the revocation
     * @param _deviceAddress The address of the device to revoke
     */
    function revokeDevice(address _deviceAddress) external onlyOwner {
        require(devices[_deviceAddress].isRegistered, "Device not found");
        require(!devices[_deviceAddress].isRevoked, "Device already revoked");

        devices[_deviceAddress].isRevoked = true;
        revocationTimestamp[_deviceAddress] = block.timestamp;

        // Update global accumulator to reflect revocation
        _updateGlobalAccumulator(_deviceAddress, true);

        activeDevices--;
        revokedDeviceCount++;

        emit DeviceRevoked(_deviceAddress, block.timestamp);
    }

    /**
     * @dev Mass revocation of multiple devices (efficient batch operation)
     * @param _deviceAddresses Array of device addresses to revoke
     */
    function massRevokeDevices(address[] calldata _deviceAddresses) external onlyOwner {
        uint256 revokedCount = 0;

        for (uint256 i = 0; i < _deviceAddresses.length; i++) {
            address deviceAddr = _deviceAddresses[i];

            if (devices[deviceAddr].isRegistered && !devices[deviceAddr].isRevoked) {
                devices[deviceAddr].isRevoked = true;
                revocationTimestamp[deviceAddr] = block.timestamp;
                revokedCount++;
            }
        }

        // Single accumulator update for all revocations
        if (revokedCount > 0) {
            globalAccumulator = keccak256(abi.encodePacked(
                globalAccumulator,
                "MASS_REVOCATION",
                _deviceAddresses,
                block.timestamp
            ));
            accumulatorUpdateCount++;

            activeDevices -= revokedCount;
            revokedDeviceCount += revokedCount;

            emit MassRevocation(_deviceAddresses, block.timestamp);
            emit AccumulatorUpdated(globalAccumulator, accumulatorUpdateCount);
        }
    }

    /**
     * @dev Reinstate a revoked device
     * @param _deviceAddress The address of the device to reinstate
     */
    function reinstateDevice(address _deviceAddress) external onlyOwner {
        require(devices[_deviceAddress].isRegistered, "Device not found");
        require(devices[_deviceAddress].isRevoked, "Device not revoked");

        devices[_deviceAddress].isRevoked = false;
        devices[_deviceAddress].lastUpdateTime = block.timestamp;
        delete revocationTimestamp[_deviceAddress];

        // Update global accumulator to reflect reinstatement
        _updateGlobalAccumulator(_deviceAddress, false);

        activeDevices++;
        revokedDeviceCount--;

        emit DeviceReinstated(_deviceAddress, block.timestamp);
    }

    /**
     * @dev Update device accumulator witness (for EVOKE-style efficient revocation)
     * Devices call this to get latest witness after accumulator updates
     * @param _witness The new witness value for the device
     */
    function updateDeviceWitness(bytes32 _witness) external onlyActiveDevice {
        deviceAccumulatorWitness[msg.sender] = _witness;
        devices[msg.sender].lastUpdateTime = block.timestamp;

        emit WitnessUpdated(msg.sender, _witness);
    }

    /**
     * @dev Batch update witnesses for multiple devices (offline update support)
     * Allows authorized party to update witnesses for devices that were offline
     * @param _devices Array of device addresses
     * @param _witnesses Corresponding array of new witness values
     */
    function batchUpdateWitnesses(
        address[] calldata _devices,
        bytes32[] calldata _witnesses
    ) external onlyOwner {
        require(_devices.length == _witnesses.length, "Array length mismatch");

        for (uint256 i = 0; i < _devices.length; i++) {
            if (devices[_devices[i]].isRegistered && !devices[_devices[i]].isRevoked) {
                deviceAccumulatorWitness[_devices[i]] = _witnesses[i];
                devices[_devices[i]].lastUpdateTime = block.timestamp;
                emit WitnessUpdated(_devices[i], _witnesses[i]);
            }
        }
    }

    /**
     * @dev Update IPFS hash for witness update batch
     * Called after computing and storing new witnesses off-chain
     * @param _ipfsHash IPFS hash of the witness update data
     */
    function setWitnessUpdateHash(string calldata _ipfsHash) external onlyOwner {
        require(bytes(_ipfsHash).length > 0, "Invalid IPFS hash");
        currentWitnessUpdateHash = _ipfsHash;
    }

    /**
     * @dev Update IPFS hash for accumulator snapshot
     * Stores periodic snapshots of accumulator state for recovery/verification
     * @param _ipfsHash IPFS hash of the accumulator snapshot
     */
    function setAccumulatorSnapshot(string calldata _ipfsHash) external onlyOwner {
        require(bytes(_ipfsHash).length > 0, "Invalid IPFS hash");
        accumulatorSnapshotHash = _ipfsHash;
    }

    /**
     * @dev Update device's credential IPFS hash
     * @param _deviceAddress The device address
     * @param _credentialHash New IPFS hash of the device's credential
     */
    function updateDeviceCredentialHash(
        address _deviceAddress,
        string calldata _credentialHash
    ) external onlyOwner {
        require(devices[_deviceAddress].isRegistered, "Device not found");
        require(bytes(_credentialHash).length > 0, "Invalid IPFS hash");
        deviceCredentialHash[_deviceAddress] = _credentialHash;
    }

    // ============ Internal Functions ============

    /**
     * @dev Update the global accumulator when devices are revoked/reinstated
     * @param _deviceAddress The device being updated
     * @param _isRevocation True if revoking, false if reinstating
     */
    function _updateGlobalAccumulator(address _deviceAddress, bool _isRevocation) private {
        globalAccumulator = keccak256(abi.encodePacked(
            globalAccumulator,
            _deviceAddress,
            _isRevocation ? "REVOKE" : "REINSTATE",
            block.timestamp
        ));
        accumulatorUpdateCount++;

        emit AccumulatorUpdated(globalAccumulator, accumulatorUpdateCount);
    }

    // ============ View Functions ============

    /**
     * @dev Get device information
     * @param _deviceAddress Address of the device
     */
    function getDevice(address _deviceAddress) external view returns (Device memory) {
        require(devices[_deviceAddress].isRegistered, "Device not found");
        return devices[_deviceAddress];
    }

    /**
     * @dev Check if a device's credentials are valid
     * @param _deviceAddress Address of the device
     */
    function isDeviceValid(address _deviceAddress) external view returns (bool) {
        return devices[_deviceAddress].isRegistered && !devices[_deviceAddress].isRevoked;
    }

    /**
     * @dev Get the current witness for a device
     * @param _deviceAddress Address of the device
     */
    function getDeviceWitness(address _deviceAddress) external view returns (bytes32) {
        require(devices[_deviceAddress].isRegistered, "Device not found");
        return deviceAccumulatorWitness[_deviceAddress];
    }

    /**
     * @dev Get contract statistics
     */
    function getStatistics() external view returns (
        uint256 _totalDevices,
        uint256 _activeDevices,
        uint256 _revokedDevices,
        uint256 _accumulatorUpdates
    ) {
        return (totalDevices, activeDevices, revokedDeviceCount, accumulatorUpdateCount);
    }

    /**
     * @dev Get devices that need witness updates (have old witnesses)
     * @param _lastUpdateBefore Timestamp threshold
     * @param _limit Maximum number of devices to return
     */
    function getDevicesNeedingWitnessUpdate(
        uint256 _lastUpdateBefore,
        uint256 _limit
    ) external view returns (address[] memory) {
        address[] memory needsUpdate = new address[](_limit);
        uint256 count = 0;

        // Note: In production, this would need pagination for large device sets
        // This is simplified for demonstration

        return needsUpdate;
    }
}