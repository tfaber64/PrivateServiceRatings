// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * Zama FHEVM:
 * - Use ONLY the official library (@fhevm/solidity/lib/FHE.sol)
 * - eaddress supports equality/ordering/bitwise (no arithmetic). We use FHE.eq + FHE.or.
 * - Avoid FHE ops in view/pure functions.
 * - Access control: FHE.allow, FHE.allowThis, FHE.makePubliclyDecryptable.
 */
import { FHE, ebool, eaddress, externalEaddress } from "@fhevm/solidity/lib/FHE.sol";

/* Network config so the contract knows on-chain KMS/ACL/Coprocessor addresses. */
import { SepoliaConfig } from "@fhevm/solidity/config/ZamaConfig.sol";

/**
 * @title PrivateListCheck
 * @notice Private membership check against encrypted whitelist/blacklist.
 *         Caller provides an encrypted address (eaddress); contract iterates encrypted set
 *         and returns ONLY an encrypted boolean (in the list / not), never exposing addresses.
 *
 *         Semantics:
 *           - Data at rest: encrypted (eaddress in storage)
 *           - On chain compute: FHE.eq(query, item) folded via FHE.or
 *           - Output: ebool (ciphertext) with ACL for msg.sender (and optionally public)
 *
 *         Public API exposes:
 *           - Admin: add/remove/clear for whitelist/blacklist (no plaintext)
 *           - User:  checkWhitelist / checkWhitelistPublic
 *                    checkBlacklist / checkBlacklistPublic
 *           - Utilities: get lengths (no addresses), last result handle, make last public
 */
contract PrivateListCheck is SepoliaConfig {
    /* ---------------- Ownable (minimal) ---------------- */
    address public owner;
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero owner");
        owner = newOwner;
    }

    /* ---------------- Encrypted sets ---------------- */
    struct Entry {
        eaddress value; // encrypted address
        bool active;    // soft-delete flag (does NOT reveal the address)
    }

    Entry[] private _whitelist;
    Entry[] private _blacklist;

    /* The very last membership result (for convenience UX) */
    ebool private _last;
    bool private _hasLast;

    /* ---------------- Events (no plaintext) ---------------- */
    event EntryAdded(bool indexed isWhitelist, uint256 indexed index);
    event EntryRemoved(bool indexed isWhitelist, uint256 indexed index);
    event SetCleared(bool indexed isWhitelist);
    event MembershipChecked(
        address indexed user,
        bool indexed isWhitelist,
        uint256 scannedCount,
        bytes32 resultHandle
    );

    /* ---------------- Admin: manage sets ---------------- */

    /**
     * @notice Add encrypted address to the whitelist.
     * @param addrExt external handle of eaddress (from Relayer SDK)
     * @param proof   integrity proof (Relayer SDK)
     * @return index  index of the entry in storage
     */
    function addToWhitelist(externalEaddress addrExt, bytes calldata proof)
        external
        onlyOwner
        returns (uint256 index)
    {
        eaddress enc = FHE.fromExternal(addrExt, proof);
        // Important: allow this contract to reuse ciphertext across future txs
        FHE.allowThis(enc);

        _whitelist.push(Entry({ value: enc, active: true }));
        index = _whitelist.length - 1;

        emit EntryAdded(true, index);
    }

    /**
     * @notice Add encrypted address to the blacklist.
     */
    function addToBlacklist(externalEaddress addrExt, bytes calldata proof)
        external
        onlyOwner
        returns (uint256 index)
    {
        eaddress enc = FHE.fromExternal(addrExt, proof);
        FHE.allowThis(enc);

        _blacklist.push(Entry({ value: enc, active: true }));
        index = _blacklist.length - 1;

        emit EntryAdded(false, index);
    }

    /**
     * @notice Soft-remove an item by index (does not reveal the address).
     */
    function removeFromWhitelist(uint256 index) external onlyOwner {
        require(index < _whitelist.length, "OOB");
        require(_whitelist[index].active, "Already removed");
        _whitelist[index].active = false;
        emit EntryRemoved(true, index);
    }

    function removeFromBlacklist(uint256 index) external onlyOwner {
        require(index < _blacklist.length, "OOB");
        require(_blacklist[index].active, "Already removed");
        _blacklist[index].active = false;
        emit EntryRemoved(false, index);
    }

    /**
     * @notice Clear sets (drops ciphertexts; safe for privacy).
     */
    function clearWhitelist() external onlyOwner {
        delete _whitelist;
        emit SetCleared(true);
    }

    function clearBlacklist() external onlyOwner {
        delete _blacklist;
        emit SetCleared(false);
    }

    /* ---------------- Views: sizes / meta (no FHE ops) ---------------- */

    function whitelistLength() external view returns (uint256) {
        return _whitelist.length;
    }

    function blacklistLength() external view returns (uint256) {
        return _blacklist.length;
    }

    function activeCounts() external view returns (uint256 wlActive, uint256 blActive) {
        uint256 n = _whitelist.length;
        for (uint256 i = 0; i < n; i++) if (_whitelist[i].active) wlActive++;
        n = _blacklist.length;
        for (uint256 j = 0; j < n; j++) if (_blacklist[j].active) blActive++;
    }

    /**
     * @notice Handle for the very last membership result (global).
     *         Decryptable by whoever was granted in the check* call, or public if made public.
     */
    function getLastResultHandle() external view returns (bytes32) {
        return _hasLast ? FHE.toBytes32(_last) : bytes32(0);
    }

    /* ---------------- Internal: core scan (no view!) ---------------- */

    function _scan(Entry[] storage set, eaddress query)
        internal
        returns (ebool found, uint256 scanned)
    {
        // Start with false; fold by OR over equality checks
        found = FHE.asEbool(false);
        uint256 n = set.length;
        for (uint256 i = 0; i < n; i++) {
            if (!set[i].active) continue;
            ebool hit = FHE.eq(query, set[i].value); // equality-only op for eaddress
            found = FHE.or(found, hit);
            scanned++;
        }
        // keep "found" decryptable by this contract for later reuse if needed
        FHE.allowThis(found);
    }

    /* ---------------- User: membership checks (private/public) ---------------- */

    /**
     * @notice Private whitelist membership check (result decryptable by the caller).
     * @return inSet ciphertext ebool: 1=in whitelist, 0=not
     */
    function checkWhitelist(externalEaddress addrExt, bytes calldata proof)
        external
        returns (ebool inSet)
    {
        eaddress q = FHE.fromExternal(addrExt, proof);
        (ebool found, uint256 scanned) = _scan(_whitelist, q);

        // ACL: the caller can decrypt the result; also store as last
        FHE.allow(found, msg.sender);
        _last = found;
        _hasLast = true;

        emit MembershipChecked(msg.sender, true, scanned, FHE.toBytes32(found));
        return found;
    }

    /**
     * @notice Public whitelist membership check (result becomes publicly decryptable).
     */
    function checkWhitelistPublic(externalEaddress addrExt, bytes calldata proof)
        external
        returns (ebool inSet)
    {
        eaddress q = FHE.fromExternal(addrExt, proof);
        (ebool found, uint256 scanned) = _scan(_whitelist, q);

        FHE.makePubliclyDecryptable(found);
        _last = found;
        _hasLast = true;

        emit MembershipChecked(msg.sender, true, scanned, FHE.toBytes32(found));
        return found;
    }

    /**
     * @notice Private blacklist membership check.
     * @return inSet ciphertext ebool: 1=in blacklist, 0=not
     */
    function checkBlacklist(externalEaddress addrExt, bytes calldata proof)
        external
        returns (ebool inSet)
    {
        eaddress q = FHE.fromExternal(addrExt, proof);
        (ebool found, uint256 scanned) = _scan(_blacklist, q);

        FHE.allow(found, msg.sender);
        _last = found;
        _hasLast = true;

        emit MembershipChecked(msg.sender, false, scanned, FHE.toBytes32(found));
        return found;
    }

    /**
     * @notice Public blacklist membership check.
     */
    function checkBlacklistPublic(externalEaddress addrExt, bytes calldata proof)
        external
        returns (ebool inSet)
    {
        eaddress q = FHE.fromExternal(addrExt, proof);
        (ebool found, uint256 scanned) = _scan(_blacklist, q);

        FHE.makePubliclyDecryptable(found);
        _last = found;
        _hasLast = true;

        emit MembershipChecked(msg.sender, false, scanned, FHE.toBytes32(found));
        return found;
    }

    /**
     * @notice Mark the last stored result as publicly decryptable (UX helper).
     */
    function makeLastPublic() external {
        require(_hasLast, "No last result");
        FHE.makePubliclyDecryptable(_last);
    }

    /* ---------------- Misc ---------------- */

    function version() external pure returns (string memory) {
        return "PrivateListCheck/1.0.0-sepolia";
    }
}
