// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title B_Evoke_Registry_ECC
 * @dev Implements EVOKE with ECC operations on Baby Jubjub curve
 * This implementation matches the EVOKE paper requirements
 *
 * Uses elliptic curve mathematics: ACC_new = ACC_old + g^element
 */
contract B_Evoke_Registry_ECC {

    // ============ Baby Jubjub Curve Parameters ============

    // Baby Jubjub prime field
    uint256 constant FIELD_MODULUS = 21888242871839275222246405745257275088548364400416034343698204186575808495617;

    // Baby Jubjub curve parameters
    uint256 constant A = 168700;
    uint256 constant D = 168696;

    // Base point (generator) on Baby Jubjub
    uint256 constant BASE_X = 5299619240641551281634865583518297030282874472190772894086521144482721001553;
    uint256 constant BASE_Y = 16950150798460657717958625567821834550301663161624707787222815936182638968203;

    // ============ Structs ============

    struct ECPoint {
        uint256 x;
        uint256 y;
    }

    struct Device {
        address deviceAddress;
        bytes32 did;
        ECPoint witness;           // ECC witness point
        uint256 registrationDate;
        uint256 lastUpdateTime;
        bool isRegistered;
        bool isRevoked;
    }

    // ============ State Variables ============

    // Global accumulator as EC point
    ECPoint public accumulator;

    // Device registry
    mapping(address => Device) public devices;
    mapping(address => uint256) public revocationTimestamp;

    // Statistics
    uint256 public totalDevices;
    uint256 public activeDevices;
    uint256 public revokedDeviceCount;
    uint256 public accumulatorUpdateCount;

    // Access control
    address public owner;

    // ============ Events ============

    event DeviceRegistered(address indexed deviceAddress, bytes32 indexed did, uint256 timestamp);
    event DeviceRevoked(address indexed deviceAddress, uint256 accX, uint256 accY, uint256 timestamp);
    event AccumulatorUpdated(uint256 newAccX, uint256 newAccY, uint256 updateCount);
    event WitnessUpdated(address indexed deviceAddress, uint256 witnessX, uint256 witnessY);

    // ============ Modifiers ============

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can perform this action");
        _;
    }

    modifier onlyRegisteredDevice() {
        require(devices[msg.sender].isRegistered, "Device is not registered");
        _;
    }

    // ============ Constructor ============

    constructor() {
        owner = msg.sender;
        // Initialize accumulator at identity point (0,1) on Baby Jubjub
        accumulator = ECPoint(0, 1);
        accumulatorUpdateCount = 1;
    }

    // ============ Baby Jubjub EC Operations ============

    /**
     * @dev Modular inverse using Fermat's little theorem
     */
    function modInverse(uint256 a) internal view returns (uint256) {
        return modExp(a, FIELD_MODULUS - 2, FIELD_MODULUS);
    }

    /**
     * @dev Modular exponentiation
     */
    function modExp(uint256 base, uint256 exponent, uint256 modulus) internal view returns (uint256 result) {
        assembly {
            let mem := mload(0x40)
            mstore(mem, 0x20)
            mstore(add(mem, 0x20), 0x20)
            mstore(add(mem, 0x40), 0x20)
            mstore(add(mem, 0x60), base)
            mstore(add(mem, 0x80), exponent)
            mstore(add(mem, 0xa0), modulus)

            let success := staticcall(gas(), 0x05, mem, 0xc0, mem, 0x20)

            switch success
            case 0 { revert(0, 0) }

            result := mload(mem)
        }
    }

    /**
     * @dev Baby Jubjub point addition
     * Implements: (x3, y3) = (x1, y1) + (x2, y2) on Baby Jubjub curve
     */
    function pointAdd(ECPoint memory p1, ECPoint memory p2) internal view returns (ECPoint memory) {
        uint256 x1 = p1.x;
        uint256 y1 = p1.y;
        uint256 x2 = p2.x;
        uint256 y2 = p2.y;

        // Baby Jubjub addition formula:
        // x3 = (x1*y2 + y1*x2) / (1 + d*x1*x2*y1*y2)
        // y3 = (y1*y2 - a*x1*x2) / (1 - d*x1*x2*y1*y2)

        uint256 x1y2 = mulmod(x1, y2, FIELD_MODULUS);
        uint256 y1x2 = mulmod(y1, x2, FIELD_MODULUS);
        uint256 x1x2 = mulmod(x1, x2, FIELD_MODULUS);
        uint256 y1y2 = mulmod(y1, y2, FIELD_MODULUS);

        uint256 dx1x2y1y2 = mulmod(D, mulmod(x1x2, y1y2, FIELD_MODULUS), FIELD_MODULUS);

        // Compute x3
        uint256 numeratorX = addmod(x1y2, y1x2, FIELD_MODULUS);
        uint256 denominatorX = addmod(1, dx1x2y1y2, FIELD_MODULUS);
        uint256 x3 = mulmod(numeratorX, modInverse(denominatorX), FIELD_MODULUS);

        // Compute y3
        uint256 ax1x2 = mulmod(A, x1x2, FIELD_MODULUS);
        uint256 numeratorY = submod(y1y2, ax1x2, FIELD_MODULUS);
        uint256 denominatorY = submod(1, dx1x2y1y2, FIELD_MODULUS);
        uint256 y3 = mulmod(numeratorY, modInverse(denominatorY), FIELD_MODULUS);

        return ECPoint(x3, y3);
    }

    /**
     * @dev Scalar multiplication on Baby Jubjub
     * Computes: point = k * BASE_POINT
     * Uses double-and-add algorithm
     */
    function scalarMul(uint256 k) internal view returns (ECPoint memory) {
        ECPoint memory result = ECPoint(0, 1); // Identity
        ECPoint memory base = ECPoint(BASE_X, BASE_Y);

        while (k > 0) {
            if (k & 1 == 1) {
                result = pointAdd(result, base);
            }
            base = pointAdd(base, base); // Point doubling
            k >>= 1;
        }

        return result;
    }

    /**
     * @dev Safe subtraction with modulo
     */
    function submod(uint256 a, uint256 b, uint256 m) internal pure returns (uint256) {
        if (a >= b) {
            return (a - b) % m;
        } else {
            return m - ((b - a) % m);
        }
    }

    // ============ Device Management Functions ============

    /**
     * @dev Register a new IoT device
     */
    function registerDevice(bytes32 _did) external {
        require(!devices[msg.sender].isRegistered, "Device is already registered");
        require(_did != bytes32(0), "Invalid DID");

        // Initial witness is the current accumulator
        devices[msg.sender] = Device({
            deviceAddress: msg.sender,
            did: _did,
            witness: ECPoint(accumulator.x, accumulator.y),
            registrationDate: block.timestamp,
            lastUpdateTime: block.timestamp,
            isRegistered: true,
            isRevoked: false
        });

        totalDevices++;
        activeDevices++;

        emit DeviceRegistered(msg.sender, _did, block.timestamp);
    }

    /**
     * @dev Revoke a device's credentials
     * Updates accumulator: A_new = A_old + g^deviceId
     */
    function revokeDevice(address _deviceAddress) external onlyOwner {
        require(devices[_deviceAddress].isRegistered, "Device not found");
        require(!devices[_deviceAddress].isRevoked, "Device already revoked");

        // Store current accumulator as witness for revoked device
        devices[_deviceAddress].witness = ECPoint(accumulator.x, accumulator.y);
        devices[_deviceAddress].isRevoked = true;
        revocationTimestamp[_deviceAddress] = block.timestamp;

        // Compute g^deviceId where deviceId is derived from address
        uint256 deviceId = uint256(uint160(_deviceAddress));
        ECPoint memory devicePoint = scalarMul(deviceId);

        // Update accumulator using point addition
        accumulator = pointAdd(accumulator, devicePoint);
        accumulatorUpdateCount++;

        activeDevices--;
        revokedDeviceCount++;

        emit DeviceRevoked(_deviceAddress, accumulator.x, accumulator.y, block.timestamp);
        emit AccumulatorUpdated(accumulator.x, accumulator.y, accumulatorUpdateCount);
    }

    /**
     * @dev Batch revoke multiple devices efficiently
     */
    function batchRevokeDevices(address[] calldata _deviceAddresses) external onlyOwner {
        uint256 revokedCount = 0;
        ECPoint memory batchAccumulator = ECPoint(accumulator.x, accumulator.y);

        for (uint256 i = 0; i < _deviceAddresses.length; i++) {
            address deviceAddr = _deviceAddresses[i];

            if (devices[deviceAddr].isRegistered && !devices[deviceAddr].isRevoked) {
                // Store witness
                devices[deviceAddr].witness = ECPoint(accumulator.x, accumulator.y);
                devices[deviceAddr].isRevoked = true;
                revocationTimestamp[deviceAddr] = block.timestamp;

                // Add device point to batch accumulator
                uint256 deviceId = uint256(uint160(deviceAddr));
                ECPoint memory devicePoint = scalarMul(deviceId);
                batchAccumulator = pointAdd(batchAccumulator, devicePoint);

                revokedCount++;
            }
        }

        if (revokedCount > 0) {
            accumulator = batchAccumulator;
            accumulatorUpdateCount++;
            activeDevices -= revokedCount;
            revokedDeviceCount += revokedCount;

            emit AccumulatorUpdated(accumulator.x, accumulator.y, accumulatorUpdateCount);
        }
    }

    /**
     * @dev Update device witness after accumulator changes
     * This maintains the equation: A = W + g^device
     */
    function updateDeviceWitness(uint256 witnessX, uint256 witnessY) external onlyRegisteredDevice {
        require(!devices[msg.sender].isRevoked, "Cannot update witness for revoked device");

        devices[msg.sender].witness = ECPoint(witnessX, witnessY);
        devices[msg.sender].lastUpdateTime = block.timestamp;

        emit WitnessUpdated(msg.sender, witnessX, witnessY);
    }

    /**
     * @dev Verify membership proof on-chain
     * Checks if: accumulator = witness + g^device
     */
    function verifyMembershipProof(
        address _deviceAddress,
        uint256 witnessX,
        uint256 witnessY
    ) external view returns (bool) {
        require(devices[_deviceAddress].isRevoked, "Device not revoked");

        // Compute g^deviceId
        uint256 deviceId = uint256(uint160(_deviceAddress));
        ECPoint memory devicePoint = scalarMul(deviceId);

        // Compute witness + g^device
        ECPoint memory computed = pointAdd(
            ECPoint(witnessX, witnessY),
            devicePoint
        );

        // Check if it equals current accumulator
        return (computed.x == accumulator.x && computed.y == accumulator.y);
    }

    // ============ View Functions ============

    function getDevice(address _deviceAddress) external view returns (Device memory) {
        require(devices[_deviceAddress].isRegistered, "Device not found");
        return devices[_deviceAddress];
    }

    function isDeviceValid(address _deviceAddress) external view returns (bool) {
        return devices[_deviceAddress].isRegistered && !devices[_deviceAddress].isRevoked;
    }

    function getAccumulator() external view returns (uint256, uint256) {
        return (accumulator.x, accumulator.y);
    }

    function getStatistics() external view returns (
        uint256 _totalDevices,
        uint256 _activeDevices,
        uint256 _revokedDevices,
        uint256 _accumulatorUpdates,
        uint256 _accX,
        uint256 _accY
    ) {
        return (
            totalDevices,
            activeDevices,
            revokedDeviceCount,
            accumulatorUpdateCount,
            accumulator.x,
            accumulator.y
        );
    }
}