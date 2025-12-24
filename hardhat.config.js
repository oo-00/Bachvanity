require("@nomicfoundation/hardhat-toolbox");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.30", // Replace with your desired compiler version
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    hardhat: {
      forking: {
        // Use an RPC URL from a provider like Alchemy, Infura, etc.
        url: `http://localhost:8545`, // Replace with your own RPC URL
      }
    }
  }
};
