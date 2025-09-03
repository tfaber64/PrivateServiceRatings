# Private List Check (ZAMA FHEVM)

Privacy-preserving whitelist/blacklist membership check on Ethereum (Sepolia) using **Fully Homomorphic Encryption (FHE)** on Zama’s FHEVM.

> **Goal:** let a user prove whether an address is **IN** or **OUT** of a confidential set **without revealing the address or the set**. Only an encrypted boolean is written on-chain; the UI publicly decrypts that boolean later. No raw addresses are ever logged to the console or sent to the chain.

---

## ✨ Features

* **Private membership check** for an input address (encrypted `eaddress`).
* **Encrypted set** of members stored on-chain; comparison uses `FHE.eq` **only**.
* **Public result**: contract marks the result `makePubliclyDecryptable`, so anyone can call `publicDecrypt(...)`.
* **Admin helpers** to add addresses to **whitelist** or **blacklist** (the UI encrypts the raw address locally before calling the contract).
* **No address leakage**: UI logs only handles, proofs, tx hashes, and decrypted booleans.
* **Pure static frontend** (no bundler needed) powered by **Zama Relayer SDK**.

---

## 🔧 Tech Stack

* **Solidity** (Zama FHEVM):

  * `import { FHE, ebool, eaddress, externalEaddress } from "@fhevm/solidity/lib/FHE.sol"`
  * Access control with `FHE.allow/allowThis` and **public decrypt** via `FHE.makePubliclyDecryptable`.
* **Frontend**: Vanilla HTML/JS + **Zama Relayer SDK** (official)

  * `createInstance`, `createEncryptedInput`, `publicDecrypt`.
  * Ethers v6 for wallet & contract calls.

> Documentation: Zama Relayer SDK — [https://docs.zama.ai/protocol/relayer-sdk-guides/](https://docs.zama.ai/protocol/relayer-sdk-guides/)

---

## 🏗️ How it works

1. The UI takes an input **address** and encrypts it in the browser via the Relayer SDK, producing a **ciphertext handle** + **proof**.
2. The contract iterates through its encrypted set (whitelist or blacklist) and uses **`FHE.eq`** to compare with the input `eaddress`.
3. The contract emits an event with a **result handle** (encrypted boolean) and flags it as **publicly decryptable**.
4. The UI invokes **`publicDecrypt`** on that handle to display **IN** or **OUT**.

**Security notes**

* Only the encrypted boolean is ever published. Raw addresses and the set members remain encrypted.
* Console logging is trimmed to exclude raw addresses.

---

## 🧱 Contract

* **Network**: Sepolia (chainId `11155111`)
* **Address**: `0x8Ac1d3E49A73F8328e43719dCF6fBfeF4405937B`
* **KMS (Sepolia)**: `0x1364cBBf2cDF5032C47d8226a6f6FBD2AFCDacAC`
* **Key methods (public result)**:

  * `checkWhitelistPublic(bytes32 addrExt, bytes proof) → bytes32`
  * `checkBlacklistPublic(bytes32 addrExt, bytes proof) → bytes32`
  * `getLastResultHandle() → bytes32`
* **Admin methods (UI encrypts the input address before calling):**

  * `addToWhitelist(bytes32 addrExt, bytes proof)`
  * `addToBlacklist(bytes32 addrExt, bytes proof)`
* **Event:** `MembershipChecked(address user, bool isWhitelist, uint256 scannedCount, bytes32 resultHandle)`

> Implementation follows Zama guidance: only `FHE.eq` over `eaddress`, **no** arithmetic on `eaddress`.

---

## 📁 Repository Layout

```
frontend/
  public/
    index.html        # Standalone UI (no build step)
contracts/
  PrivateListCheck.sol
scripts/              # optional
hardhat.config.ts     # if you use Hardhat for local tasks
```

---

## 🚀 Quick Start (Frontend)

**Prerequisites:** MetaMask, Node.js (optional for serving static files).

### Option A — open as a static file

* Open `frontend/public/index.html` directly in a modern browser.
* If your browser blocks crypto features from file://, use Option B below.

### Option B — serve locally

```bash
# from repo root
npx serve frontend/public -p 5173    # or any static server
# then open http://localhost:5173
```

Alternatives:

```bash
# python
python3 -m http.server --directory frontend/public 5173
# or
npx http-server frontend/public -p 5173 --cors
```

### Using the dApp

1. Click **Connect MetaMask** (network auto-switches to **Sepolia** if needed).
2. Choose **Whitelist** or **Blacklist** and paste an address to check (0x…).
3. Press **Check** → the app encrypts & sends, then shows **IN** or **OUT**.
4. You can later press **Decrypt Last Result** to re-decrypt the last emitted handle.

### Admin (optional)

* As the contract owner, paste an address into the **Admin** panel and use:

  * **Add to Whitelist** or **Add to Blacklist** — the UI encrypts the address, then calls the contract.

---

## 🧩 Installation (full project)

```bash
# 1) Clone
git clone https://github.com/<your-org>/<your-repo>.git
cd <your-repo>

# 2) (optional) Install deps if you plan to compile/deploy contracts
npm i

# 3) Frontend — run a static server
npx serve frontend/public -p 5173
```

**Download as ZIP:**
If this repo is on GitHub, you can download directly:

```
https://github.com/<your-org>/<your-repo>/archive/refs/heads/main.zip
```

> Replace `<your-org>/<your-repo>` with your namespace.

---

## 🔗 Relayer/Gateway (Testnet)

* **Relayer URL**: `https://relayer.testnet.zama.cloud`
* **Chain**: Sepolia `11155111`
* **KMS**: `0x1364cBBf2cDF5032C47d8226a6f6FBD2AFCDacAC`

---

## 🧪 Console Logging

The console prints only:

* encryption **handle** and **proof** length (never raw addresses),
* transaction hash and receipt summary,
* the decrypted boolean value.

To disable logging entirely, search for the small `clog` helper in `index.html` and no-op the calls.

---

## ❗ Troubleshooting

* **“Handle … is not allowed for public decryption”**
  You likely called a non-public method. Use `checkWhitelistPublic` / `checkBlacklistPublic` from the UI.
* **Invalid address**
  The UI requires EIP-55 compatible `0x` address (40 hex chars). It validates before sending.
* **Wrong network**
  MetaMask must be on **Sepolia**. The app will try to switch automatically.

---

## ✅ License

MIT — feel free to use and adapt.
