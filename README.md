# <h1 align="center"> 再保险区块链案例 </h1>

# 简介
这是一个基于以太坊的再保险区块链案例，旨在展示如何使用 Solidity 编写智能合约来模拟再保险业务流程。该项目包括以下主要功能：
- **再保险合约**：实现再保险的基本逻辑，包括保单创建、索赔处理等。
- **索赔处理**：处理索赔请求，验证索赔条件。
- **托管合约**：用于管理再保险资金的托管，确保资金安全。


# 运行
```bash
# 安装依赖
curl -L https://foundry.paradigm.xyz | bash
foundryup
npm install
```
# 启动

```bash
# 启动本地私链
./demo_scripts/01.start_private_chain.sh
```
根据anvil输出的账户私钥  

    Private Keys
    ==================

    (0) 0xac0974▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇784d7bf4f2ff80
    (1) 0x59c699▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇f4603b6b78690d
    (2) 0x5de411▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇▇b9a804cdab365a

修改
`demo_scripts/02.deploy_contract.sh` 中的 `INSURED_PK` ，`CEDENT_PK` 和 `REINSURER_PK` 为上面输出的账户私钥。
```bash
# 部署合约
./demo_scripts/02.deploy_contract.sh
```
