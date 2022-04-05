let Vanity = artifacts.require("Vanity");
module.exports = async function(deployer) {
    await deployer.deploy(Vanity);
};