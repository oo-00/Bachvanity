// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Bachvanity is Ownable {

    // Constants and state variables
    uint256 public constant DENOM = 10000;
    uint256 public constant maxLateClaimCallFee = 500; // max 5% fee
    uint256 public lateClaimCallFee = 100; // 1% fee for late claim calls
    uint256 public maxDeadline = 180 days;
    uint256 public minDeadline = 24 hours;
    uint256 public lateClaimDelay = 7 days;

    struct Orders {
        address requestOwner;
        uint256 amount;
        bytes32 bytecodeHash;
        address deployer;
        bytes1[40] desired;
        uint8 maxPoints;
        uint8 currentPoints;
        uint160 deadline;
        bytes32 bestSalt;
        address bestSubmitter;
    }
    Orders[] public orders;
    mapping(address => uint256[]) public userOrderIDs;

    // Events
    event Deployed(address addr, bytes32 salt);
    event OrderCreated(uint256 orderId, address requestOwner, uint256 amount, bytes32 bytecodeHash, address deployer, string addressPattern, uint160 deadline);
    event SaltSubmitted(uint256 orderId, address submitter, bytes32 salt, uint8 points);
    event OrderClosed(uint256 orderId, address winner, uint256 amount);

    // Constructor
    constructor(address _owner) Ownable(_owner) {}

    // View functions
    /*
    * @return total number of orders
    */
    function ordersLength() public view returns (uint256) {
        return orders.length;
    }

    /*
    * @return number of orders created by user
    */
    function userOrderIDsLength(address user) public view returns (uint256) {
        return userOrderIDs[user].length;
    }

    /*
    * @dev compute address for given salt, bytecodeHash and deployer
    * @param salt used for address computation
    * @param bytecodeHash keccak256 hash of the contract bytecode (INCLUDING constructor args) to be deployed 
    * @param create2 factory that will deploy the contract
    * @return computed address for given salt, bytecodeHash and deployer
    */
    function computeAddress(bytes32 salt, bytes32 bytecodeHash, address deployer) public pure returns (address addr) {
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(add(ptr, 0x40), bytecodeHash)
            mstore(add(ptr, 0x20), salt)
            mstore(ptr, deployer)
            let start := add(ptr, 0x0b)
            mstore8(start, 0xff)
            addr := and(keccak256(start, 85), 0xffffffffffffffffffffffffffffffffffffffff)
        }
    }

    /*
    * @dev simulate points for given salt in order
    * @param orderId id of the order
    * @param salt salt to simulate
    * @return points for given salt in order
    */
    function simPoints(uint256 orderId, bytes32 salt) public view returns(uint8) {
        Orders memory order = orders[orderId];
        bytes32 bytecodeHash = order.bytecodeHash;
        address deployer = order.deployer;
        address addr = computeAddress(salt, bytecodeHash, deployer);
        bytes memory addrBytes = bytes(Strings.toHexString(uint256(uint160(addr)), 20));
        uint8 points = 0;
        for(uint256 i = 2; i < addrBytes.length; i++) {
            if(order.desired[i - 2] == addrBytes[i]) {
                points++;
            }
        }
        return points;
    }

    // Write functions
    /*
    * @dev create a vanity address request
    * @param deployer address that will deploy the contract, if address(0) then this contract will deploy
    * @param bytecodeHash keccak256 hash of the contract bytecode to be deployed
    * @param addressPattern desired address pattern as hex string, use 'X' for wildcard characters, e.g. 'deadbeefXXXXXX...'
    * @param deadline timestamp until which the request is valid
    */
    function createRequest(address deployer, bytes32 bytecodeHash, string memory addressPattern, uint160 deadline) public payable {
        require(msg.value > DENOM, "!minValue");
        require(deadline > block.timestamp + minDeadline, "!deadline");
        require(deadline - block.timestamp <= maxDeadline, "!maxDeadline");
        if(deployer == address(0)) {
            deployer = address(this);
        }
        bytes memory b = bytes(addressPattern);
        uint256 l = b.length;
        require(l == 40, "!addressLength");
        bytes1[40] memory out;
        uint8 maxPoints = 40;
        for (uint256 i = 0; i < b.length; i++) {
            out[i] = b[i];
            require((out[i] >= 0x30 && out[i] <= 0x39) || (out[i] >= 0x61 && out[i] <= 0x66) || out[i] == 0x58, "!invalidChars");
            if(out[i] == 0x58) {
                maxPoints--;
            }
        }
        require(maxPoints > 0, "!maxPoints");
        orders.push(Orders({
            requestOwner: msg.sender,
            amount: msg.value,
            bytecodeHash: bytecodeHash,
            deployer: deployer,
            desired: out,
            maxPoints: maxPoints,
            currentPoints: 0,
            deadline: deadline,
            bestSalt: bytes32(0),
            bestSubmitter: address(0)
        }));
        userOrderIDs[msg.sender].push(orders.length - 1);
        emit OrderCreated(orders.length - 1, msg.sender, msg.value, bytecodeHash, deployer, addressPattern, deadline);
    }

    /*
    * @dev submit a salt for given order
    * @param orderId id of the order
    * @param salt salt to submit
    */
    function submitSalt(uint256 orderId, bytes32 salt) public {
        Orders storage order = orders[orderId];
        require(block.timestamp <= order.deadline, "!deadline");
        bytes32 bytecodeHash = order.bytecodeHash;
        address deployer = order.deployer;
        address addr = computeAddress(salt, bytecodeHash, deployer);
        bytes memory addrBytes = bytes(Strings.toHexString(uint256(uint160(addr)), 20));
        uint8 points = 0;
        for(uint256 i = 2; i < addrBytes.length; i++) {
            if(order.desired[i - 2] == addrBytes[i]) {
                points++;
            }
        }
        require(points > order.currentPoints, "!improve");
        order.currentPoints = points;
        order.bestSalt = salt;
        order.bestSubmitter = msg.sender;
        emit SaltSubmitted(orderId, msg.sender, salt, points);
        if(points == order.maxPoints) {
            // perfect match, payout immediately
            uint256 amount = order.amount;
            order.amount = 0;
            (bool success, ) = msg.sender.call{value: amount}("");
            require(success, "!transfer");
            emit OrderClosed(orderId, msg.sender, amount);
        }
    }

    /*
    * @dev claim reward after deadline (winner only)
    * @param orderId id of the order
    */
    function claimReward(uint256 orderId) public {
        Orders storage order = orders[orderId];
        require(block.timestamp > order.deadline, "!deadline");
        address winner = order.bestSubmitter;
        uint256 amount = order.amount;
        require(amount > 0, "!claimed");
        order.amount = 0; // prevent re-entrancy by setting amount to 0 before any transfers
        if(msg.sender != winner && block.timestamp > order.deadline + lateClaimDelay) {
            uint256 fee = (amount * lateClaimCallFee) / DENOM;
            amount -= fee;
            (bool feeSuccess, ) = msg.sender.call{value: fee}("");
            require(feeSuccess, "!feeTransfer");
        }
        (bool success, ) = winner.call{value: amount}("");
        require(success, "!transfer");
        emit OrderClosed(orderId, winner, amount);
    }

    /*
    * @dev claim back funds after deadline (if no winner)
    * @param orderId id of the order
    */
    function claimDeadOrder(uint256 orderId) public {
        Orders storage order = orders[orderId];
        require(block.timestamp > order.deadline, "!deadline");
        require(order.bestSubmitter == address(0), "!hasBest");
        require(order.requestOwner == msg.sender, "!notOwner");
        uint256 amount = order.amount;
        require(amount > 0, "!claimed");
        order.amount = 0;
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "!transfer");
        emit OrderClosed(orderId, address(0), 0);
    }

    /*
    * @dev deploy contract using create2
    * @param code contract bytecode
    * @param salt salt used for create2
    */
    function deploy(bytes memory code, bytes32 salt) public {
        address addr;
        assembly {
            addr := create2(0, add(code, 0x20), mload(code), salt)
            if iszero(extcodesize(addr)) {
                revert(0, 0)
            }
        }
        emit Deployed(addr, salt);
    }

    // Owner functions to update parameters

    /*
    * @dev update late claim call fee
    * @param _lateClaimCallFee new late claim call fee
    */
    function updateLateClaimCallFee(uint256 _lateClaimCallFee) public onlyOwner {
        require(_lateClaimCallFee <= DENOM, "!invalidFee");
        lateClaimCallFee = _lateClaimCallFee;
    }

    /*
    * @dev update minimum deadline
    * @param _minDeadline new minimum deadline
    */
    function updateMinDeadline(uint256 _minDeadline) public onlyOwner {
        minDeadline = _minDeadline;
    }

    /*
    * @dev update maximum deadline
    * @param _maxDeadline new maximum deadline
    */
    function updateMaxDeadline(uint256 _maxDeadline) public onlyOwner {
        require(_maxDeadline >= 7 days, "!invalidMaxDeadline");
        maxDeadline = _maxDeadline;
    }

    /*
    * @dev update late claim delay
    * @param _lateClaimDelay new late claim delay
    */
    function updateLateClaimDelay(uint256 _lateClaimDelay) public onlyOwner {
        require(_lateClaimDelay >= 24 hours, "!invalidLateClaimDelay");
        lateClaimDelay = _lateClaimDelay;
    }

}