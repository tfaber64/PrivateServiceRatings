// deploy/001_deploy_private_list_check.ts
import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const func: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments, getNamedAccounts, network, ethers, run } = hre;
  const { deploy, log, read } = deployments;

  const { deployer } = await getNamedAccounts();
  const chainId = await hre.getChainId();

  log("----------------------------------------------------");
  log(`Network: ${network.name} (chainId=${chainId})`);
  log(`Deployer: ${deployer}`);

  // Немного полезной диагностики (не требует .env)
  const bal = await ethers.provider.getBalance(deployer);
  const fee = await ethers.provider.getFeeData();
  log(`Deployer balance: ${ethers.formatEther(bal)} ETH`);
  log(
    `FeeData: gasPrice=${fee.gasPrice?.toString() ?? "—"} | maxFeePerGas=${fee.maxFeePerGas?.toString() ?? "—"} | maxPriorityFeePerGas=${fee.maxPriorityFeePerGas?.toString() ?? "—"}`
  );

  // Деплой без аргументов; явно указываем имя контракта
  const res = await deploy("PrivateListCheck", {
    contract: "PrivateListCheck",
    from: deployer,
    args: [],
    log: true,
    // waitConfirmations: 1, // при желании можно увеличить на L2/медленных RPC
    // deterministicDeployment: false,
  });

  log(`✅ PrivateListCheck deployed at: ${res.address}`);
  if (res.transactionHash) log(`   tx: ${res.transactionHash}`);

  // Пробуем прочитать version() для валидации
  try {
    const version: string = await read("PrivateListCheck", "version");
    log(`ℹ️ version(): ${version}`);
  } catch (e) {
    log(`(warn) version() read failed: ${(e as Error).message}`);
  }

  // Опциональная верификация на Etherscan (если настроен ключ, но .env править не нужно)
  // Попытаемся аккуратно, без падения, только когда есть API-ключ в окружении.
  if (network.name !== "hardhat" && process.env.ETHERSCAN_API_KEY) {
    try {
      log("🔎 Verifying on Etherscan…");
      await run("verify:verify", {
        address: res.address,
        constructorArguments: [],
      });
      log("✅ Etherscan verification done");
    } catch (e) {
      log(`(warn) verify skipped/failed: ${(e as Error).message}`);
    }
  } else {
    log("🔎 Verify skipped (no ETHERSCAN_API_KEY or local network).");
  }

  log("----------------------------------------------------");
};

export default func;
func.id = "deploy_PrivateListCheck";
func.tags = ["PrivateListCheck"];
