// SPDX-License-Identifier: LicenseRef-Degensoft-Aqua-Source-1.1

import { deployAndGetContract } from '@1inch/solidity-utils';
import { DeployFunction } from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: any) {
    const { getNamedAccounts, deployments, ethers } = hre;

    console.log('Starting Aqua deployment...\n');

    // Get deployer address (returns a string)
    const { deployer } = await getNamedAccounts();

    const network = await ethers.provider.getNetwork();
    const chainId = network.chainId;

    console.log('Network:', chainId.toString());
    console.log('Deployer address:', deployer);

    // Deploy Aqua contract
    console.log('Deploying Aqua contract...');
    const aqua = await deployAndGetContract({
        contractName: 'Aqua',
        constructorArgs: [],
        deployer,
        deployments,
        skipVerify: true,
    });
    const aquaAddress = await aqua.getAddress();
    console.log('Aqua deployed to:', aquaAddress);

    // Deploy XYCSwap contract
    console.log('\nDeploying XYCSwap contract...');
    const xycSwap = await deployAndGetContract({
        contractName: 'XYCSwap',
        constructorArgs: [aquaAddress],
        deployer: deployer,
        deployments,
        skipVerify: true,
    });
    const xycSwapAddress = await xycSwap.getAddress();
    console.log('XYCSwap deployed to:', xycSwapAddress);

    // Deploy SwapExecutor (resolver) contract only if DEPLOY_RESOLVER is set
    if (process.env.DEPLOY_RESOLVER === 'true') {
        console.log('\nDeploying SwapExecutor contract...');
        const swapExecutor = await deployAndGetContract({
            contractName: 'SwapExecutor',
            constructorArgs: [aquaAddress],
            deployer: deployer,
            deployments,
            skipVerify: true,
        });
        const swapExecutorAddress = await swapExecutor.getAddress();
        console.log('SwapExecutor deployed to:', swapExecutorAddress);
    } else {
        console.log('\nSkipping SwapExecutor deployment (set DEPLOY_RESOLVER=true to deploy)');
    }

    console.log('\n✅ Deployment completed successfully!');
};

export default func;
func.tags = ['Aqua'];
