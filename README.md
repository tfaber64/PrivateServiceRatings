# Private Service Ratings (FHEVM)

Aggregated-only, privacy-preserving ratings on Ethereum (Sepolia) using **Zama FHEVM**.
Users submit encrypted 1–5 star ratings. The contract stores **only encrypted aggregates** (sum & count). No individual scores are revealed on-chain.

> Frontend is a single static page: `frontend/public/index.html`
> Contract network: **Sepolia**
> Example deployed contract: `0x9555EbB0972CA12bd0d8677178375c3bE0Ced8D`

---

## ✨ Features

* **Private rating submission (1..5)** for any service key (free text like `cafe-venue-42`).
* **Duplicate protection** in plaintext: users can rate each service **once** (`hasRated`).
* **Encrypted aggregates only**: contract keeps `sum` and `count` (both FHE-encrypted).
* **Two decrypt modes for reading aggregates**:

  * `publicDecrypt` if the owner made aggregates public.
  * `userDecrypt` with a signed EIP‑712 request (private to the reader).
* **Owner tools**:

  * `initService(serviceKey)` to create/reset encrypted aggregates.
  * `makeAggregatesPublic(serviceKey)` to mark aggregates public-decryptable.

---

## 🧠 How it works

* Frontend encrypts your rating with **Relayer SDK 0.2.0** → produces `externalEuint32` + attestation (`proof`).
* Contract converts it to `euint32`, validates `1 ≤ rating ≤ 5` **inside FHE**, then updates:

  * `sum = sum + rating`
  * `count = count + 1`
* No individual ratings are stored/emitted. Only encrypted `sum` and `count` remain on-chain.
* After `submitRating`, the contract grants the **sender** read permission to current aggregates, so `userDecrypt` works even if not public.

---

## 🧩 Contract API

```solidity
function initService(bytes32 serviceId) external onlyOwner;
function makeAggregatesPublic(bytes32 serviceId) external onlyOwner;
function submitRating(bytes32 serviceId, externalEuint32 ratingExt, bytes calldata proof) external;
function hasRated(bytes32 serviceId, address user) external view returns (bool);
function getAggregateHandles(bytes32 serviceId) external view returns (bytes32 sumH, bytes32 countH);
function version() external pure returns (string memory);
function owner() external view returns (address);
```

> The **service key** used in the UI is hashed to `bytes32` inside the app with `keccak256(utf8(serviceKey))` and sent as `serviceId`.

---

## 🖥️ Frontend

Single static file: `frontend/public/index.html`
Stack: plain HTML/CSS/JS + **ethers v6** + **Relayer SDK 0.2.0** (ESM via CDN).

### Configure addresses

Open `frontend/public/index.html` and adjust the config block:

```js
const CONFIG = {
  NETWORK_NAME: "Sepolia",
  CHAIN_ID_HEX: "0xaa36a7",
  RELAYER_URL: "https://relayer.testnet.zama.cloud",
  // 👉 Put your deployed address here
  CONTRACT_ADDRESS: "0x9555EbB0972CA12bd0d8677178375c3bE0Ced8D",
};
```

---

## 🚀 Run locally

No build step required; just serve the static file.

**Option A — `serve`**

```bash
npm i -g serve
serve frontend/public -p 5173
```

Open [http://localhost:5173](http://localhost:5173)

**Option B — Python**

```bash
cd frontend/public
python3 -m http.server 5173
```

Open [http://localhost:5173](http://localhost:5173)

> Requirements: MetaMask on **Sepolia** with a bit of test ETH.

---

## 🔧 Owner quickstart

1. Open the app and **connect owner wallet** (MetaMask).
2. In *Admin Tools*, type a **Service key** (e.g., `cafe-venue-42`).
3. Click **Init/Reset Service** (creates encrypted `sum`/`count`).
4. *(Optional)* Click **Make Aggregates Public** to allow `publicDecrypt` for everyone.

---

## 👤 User flow

1. Enter the **Service key** (must match owner’s key exactly).
2. Select a **rating** (1..5).
3. Click **Submit Encrypted Rating** — the UI encrypts locally and sends to the contract; a tx hash is shown.
4. Read **Aggregates** → *sum* / *count*:

   * If public → uses `publicDecrypt`.
   * If not public → the app asks for an **EIP‑712 signature** and reads privately via `userDecrypt`.

---

## 🐞 Troubleshooting

* **“Ensure the service exists.”**
  The owner must call **Init/Reset Service** for this key first.

* **Make-public transaction reverted**
  Ensure you are the contract owner and that the service was initialized. The current contract refreshes ciphertexts before calling `makePubliclyDecryptable`.

* **No decrypt result**
  Check you’re on **Sepolia**, the service key matches exactly, and accept the **EIP‑712 signing** dialog for `userDecrypt`.

---

## 🔐 Privacy notes

* No individual rating is stored or emitted.
* Only encrypted `sum` and `count` exist on-chain.
* `hasRated(service, user)` is plaintext (anti-double-vote only).
* Public decrypt is **opt‑in** per service by the owner.

---

## 🛠 Tech

* Zama **FHEVM**
* **Relayer SDK**: `0.2.0`
* **ethers**: v6
* Solidity `^0.8.24`

---

## 📄 Project layout

```
.
├─ contracts/                 # Solidity sources
├─ frontend/
│  └─ public/
│     └─ index.html          # The app (single-file)
└─ README.md
```

---

## 📌 Environment

* Network: **Sepolia** (`chainId 11155111` / `0xaa36a7`)
* Relayer (testnet): `https://relayer.testnet.zama.cloud`
* Example contract: `0x9555EbB0972CA12bd0d8677178375c3bE0Ced8D`

---

## 🧾 License

MIT — add `LICENSE` if your repo doesn’t have one yet.

---

## 🙌 Acknowledgements

Thanks to the Zama team for FHEVM & tooling and to the Ethereum community for open infrastructure.
