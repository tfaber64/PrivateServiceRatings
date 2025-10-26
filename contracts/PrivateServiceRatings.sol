// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * Private Service Ratings (Aggregated Only) — v1.1
 * - Рейтинги 1..5, агрегируются как sum/count (оба euint32).
 * - Дубли по user+service запрещены (plain bool).
 * - submitRating: всегда выдаём право чтения агрегатов отправителю (userDecrypt).
 * - makeAggregatesPublic: пересоздаём шифротексты (sum' = sum + 0), и уже на них делаем makePubliclyDecryptable.
 */

import { FHE, ebool, euint32, externalEuint32 } from "@fhevm/solidity/lib/FHE.sol";
import { SepoliaConfig } from "@fhevm/solidity/config/ZamaConfig.sol";

contract PrivateServiceRatings is SepoliaConfig {
    /* ---------------------------- Version & Ownership ---------------------------- */

    function version() external pure returns (string memory) {
        return "PrivateServiceRatings/1.1.0";
    }

    address public owner;
    modifier onlyOwner() { require(msg.sender == owner, "Not owner"); _; }

    constructor() { owner = msg.sender; }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero owner");
        owner = newOwner;
    }

    /* --------------------------------- Storage ---------------------------------- */

    struct Aggregates {
        bool exists;
        euint32 sum;
        euint32 count;
    }

    mapping(bytes32 => Aggregates) private _svc;
    mapping(bytes32 => mapping(address => bool)) private _rated;

    /* ---------------------------------- Events ---------------------------------- */

    event RatingSubmitted(bytes32 indexed serviceId, address indexed rater, bytes32 sumHandle, bytes32 countHandle);
    event ServiceInitialized(bytes32 indexed serviceId);
    event AggregatesMadePublic(bytes32 indexed serviceId);

    /* ------------------------------- Admin: init -------------------------------- */

    function initService(bytes32 serviceId) external onlyOwner {
        Aggregates storage A = _svc[serviceId];
        A.exists = true;
        A.sum   = FHE.asEuint32(0);
        A.count = FHE.asEuint32(0);

        // Контракту нужно уметь читать/переиспользовать свои агрегаты
        FHE.allowThis(A.sum);
        FHE.allowThis(A.count);

        emit ServiceInitialized(serviceId);
    }

    /**
     * Публичная расшифровка: пересоздаём шифротекст в текущем контексте (sum2=sum+0),
     * даём себе доступ и делаем public.
     */
    function makeAggregatesPublic(bytes32 serviceId) external onlyOwner {
        Aggregates storage A = _svc[serviceId];
        require(A.exists, "Service not found");

        // Пересоздаём шифротексты в этой же транзакции
        euint32 sum2   = FHE.add(A.sum,   FHE.asEuint32(0));
        euint32 count2 = FHE.add(A.count, FHE.asEuint32(0));

        // Контракт читает новые значения
        FHE.allowThis(sum2);
        FHE.allowThis(count2);

        // Помечаем новые шифротексты как публичные
        FHE.makePubliclyDecryptable(sum2);
        FHE.makePubliclyDecryptable(count2);

        // Сохраняем обратно (можно и не сохранять, но так консистентнее)
        A.sum   = sum2;
        A.count = count2;

        emit AggregatesMadePublic(serviceId);
    }

    /* ------------------------------ Submit rating ------------------------------- */

    function submitRating(
        bytes32 serviceId,
        externalEuint32 ratingExt,
        bytes calldata proof
    ) external {
        Aggregates storage A = _svc[serviceId];
        require(A.exists, "Service not found");
        require(!_rated[serviceId][msg.sender], "Already rated");

        // Десериализация
        euint32 rating = FHE.fromExternal(ratingExt, proof);

        // 1..5 ?
        ebool okLow  = FHE.ge(rating, FHE.asEuint32(1));
        ebool okHigh = FHE.le(rating, FHE.asEuint32(5));
        ebool valid  = FHE.and(okLow, okHigh);

        // valid ? rating : 0
        euint32 incVal = FHE.select(valid, rating, FHE.asEuint32(0));
        // valid ? 1 : 0
        euint32 incCnt = FHE.select(valid, FHE.asEuint32(1), FHE.asEuint32(0));

        // Новые агрегаты
        euint32 newSum   = FHE.add(A.sum,   incVal);
        euint32 newCount = FHE.add(A.count, incCnt);

        // Разрешить контракту повторно использовать
        FHE.allowThis(newSum);
        FHE.allowThis(newCount);

        // Сохраняем
        A.sum   = newSum;
        A.count = newCount;

        // 🔓 Разрешаем отправителю приватное чтение агрегатов (userDecrypt)
        FHE.allow(A.sum,   msg.sender);
        FHE.allow(A.count, msg.sender);

        _rated[serviceId][msg.sender] = true;

        emit RatingSubmitted(serviceId, msg.sender, FHE.toBytes32(A.sum), FHE.toBytes32(A.count));
    }

    /* --------------------------------- Getters ---------------------------------- */

    function hasRated(bytes32 serviceId, address user) external view returns (bool) {
        return _rated[serviceId][user];
    }

    function getAggregateHandles(bytes32 serviceId) external view returns (bytes32 sumH, bytes32 countH) {
        Aggregates storage A = _svc[serviceId];
        require(A.exists, "Service not found");
        return (FHE.toBytes32(A.sum), FHE.toBytes32(A.count));
    }
}
