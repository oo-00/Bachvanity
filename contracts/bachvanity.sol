// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/utils/Strings.sol";

contract Bachvanity {

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

    event Deployed(address addr, bytes32 salt);

    function ordersLength() public view returns (uint256) {
        return orders.length;
    }
    function userOrderIDsLength(address user) public view returns (uint256) {
        return userOrderIDs[user].length;
    }

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

    function createRequest(address deployer, bytes32 bytecodeHash, string memory addressPattern, uint160 deadline) public payable {
        require(msg.value > 0, "!value");
        require(deadline > block.timestamp, "!deadline");
        require(deadline - block.timestamp <= 60 days, "!maxDeadline");
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
    }

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
        if(points == order.maxPoints) {
            // perfect match, payout immediately
            uint256 amount = order.amount;
            order.amount = 0;
            (bool success, ) = msg.sender.call{value: amount}("");
            require(success, "!transfer");
        }
    }

    function claimReward(uint256 orderId) public {
        Orders storage order = orders[orderId];
        require(block.timestamp > order.deadline, "!deadline");
        require(order.bestSubmitter == msg.sender, "!notBest");
        uint256 amount = order.amount;
        require(amount > 0, "!claimed");
        order.amount = 0;
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "!transfer");
    }

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
    }

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
}
