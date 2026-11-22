// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function decimals() external view returns (uint8);
}

/**
 * @title AevumPayGuard
 * @notice Scoped-budget agentic invoice & Confirmation-of-Payee settlement contract for QDay Aevum Testnet (tUSD8).
 * @dev Designed for QDay Aevum Testnet (Chain ID 44005) with tUSD8 (0x456569838f1d43009A91ebA4263147Afd7233483, 6 decimals).
 */
contract AevumPayGuard {
    IERC20 public immutable stablecoin;
    uint256 private _locked = 1;

    struct PayeeProfile {
        string handle;
        bytes32 identityHash;
        bool active;
        uint64 registeredAt;
    }

    struct SpendingSession {
        address payer;
        address agent;
        uint256 maxBudget;
        uint256 spent;
        uint256 perTxCap;
        uint64 expiresAt;
        bool revoked;
        bool requireVerifiedPayee;
    }

    struct Invoice {
        address payee;
        uint256 amount;
        uint64 dueAt;
        bytes32 memoHash;
        bool paid;
        bool cancelled;
        address paidBy;
        uint64 paidAt;
        bytes32 paidViaSession;
    }

    mapping(address => PayeeProfile) public payees;
    mapping(bytes32 => SpendingSession) public sessions;
    mapping(bytes32 => Invoice) public invoices;

    uint256 public sessionNonce;
    uint256 public invoiceNonce;

    event PayeeRegistered(address indexed payee, string handle, bytes32 identityHash);
    event PayeeStatusUpdated(address indexed payee, bool active);
    event SessionCreated(
        bytes32 indexed sessionId,
        address indexed payer,
        address indexed agent,
        uint256 maxBudget,
        uint256 perTxCap,
        uint64 expiresAt,
        bool requireVerifiedPayee
    );
    event SessionRevoked(bytes32 indexed sessionId, address indexed payer);
    event InvoiceCreated(
        bytes32 indexed invoiceId,
        address indexed payee,
        uint256 amount,
        uint64 dueAt,
        bytes32 memoHash
    );
    event InvoiceCancelled(bytes32 indexed invoiceId, address indexed payee);
    event InvoicePaid(
        bytes32 indexed invoiceId,
        address indexed payer,
        address indexed payee,
        uint256 amount,
        bytes32 sessionId
    );

    error ReentrancyBlocked();
    error InvalidAddress();
    error InvalidAmount();
    error InvalidExpiry();
    error Unauthorized();
    error SessionInactive();
    error SessionExpired();
    error ExceedsPerTxCap();
    error ExceedsSessionBudget();
    error UnverifiedPayee();
    error InvoiceNotFound();
    error InvoiceAlreadySettled();
    error InvoiceOverdue();
    error TransferFailed();

    modifier nonReentrant() {
        if (_locked != 1) revert ReentrancyBlocked();
        _locked = 2;
        _;
        _locked = 1;
    }

    constructor(address stablecoinAddress) {
        if (stablecoinAddress == address(0)) revert InvalidAddress();
        stablecoin = IERC20(stablecoinAddress);
    }

    /// @notice Register or update a Confirmation-of-Payee record for msg.sender.
    function registerPayee(string calldata handle, bytes32 identityHash) external {
        if (bytes(handle).length == 0) revert InvalidAmount();
        payees[msg.sender] = PayeeProfile({
            handle: handle,
            identityHash: identityHash,
            active: true,
            registeredAt: uint64(block.timestamp)
        });
        emit PayeeRegistered(msg.sender, handle, identityHash);
    }

    /// @notice Pause or reactivate Confirmation-of-Payee status.
    function setPayeeActive(bool active) external {
        if (payees[msg.sender].registeredAt == 0) revert Unauthorized();
        payees[msg.sender].active = active;
        emit PayeeStatusUpdated(msg.sender, active);
    }

    /// @notice Create a least-privilege spending session allowing an agent to settle tUSD8 invoices within strict caps.
    function createSession(
        address agent,
        uint256 maxBudget,
        uint256 perTxCap,
        uint64 expiresAt,
        bool requireVerifiedPayee
    ) external returns (bytes32 sessionId) {
        if (agent == address(0)) revert InvalidAddress();
        if (maxBudget == 0 || perTxCap == 0 || perTxCap > maxBudget) revert InvalidAmount();
        if (expiresAt <= uint64(block.timestamp)) revert InvalidExpiry();

        sessionId = keccak256(
            abi.encodePacked(block.chainid, address(this), msg.sender, agent, ++sessionNonce)
        );
        sessions[sessionId] = SpendingSession({
            payer: msg.sender,
            agent: agent,
            maxBudget: maxBudget,
            spent: 0,
            perTxCap: perTxCap,
            expiresAt: expiresAt,
            revoked: false,
            requireVerifiedPayee: requireVerifiedPayee
        });

        emit SessionCreated(
            sessionId,
            msg.sender,
            agent,
            maxBudget,
            perTxCap,
            expiresAt,
            requireVerifiedPayee
        );
    }

    /// @notice Immediately revoke an active spending session.
    function revokeSession(bytes32 sessionId) external {
        SpendingSession storage s = sessions[sessionId];
        if (s.payer != msg.sender) revert Unauthorized();
        s.revoked = true;
        emit SessionRevoked(sessionId, msg.sender);
    }

    /// @notice Issue a verifiable on-chain tUSD8 invoice.
    function createInvoice(
        uint256 amount,
        uint64 dueAt,
        bytes32 memoHash
    ) external returns (bytes32 invoiceId) {
        if (amount == 0) revert InvalidAmount();
        if (dueAt <= uint64(block.timestamp)) revert InvalidExpiry();

        invoiceId = keccak256(
            abi.encodePacked(block.chainid, address(this), msg.sender, amount, memoHash, ++invoiceNonce)
        );
        invoices[invoiceId] = Invoice({
            payee: msg.sender,
            amount: amount,
            dueAt: dueAt,
            memoHash: memoHash,
            paid: false,
            cancelled: false,
            paidBy: address(0),
            paidAt: 0,
            paidViaSession: bytes32(0)
        });

        emit InvoiceCreated(invoiceId, msg.sender, amount, dueAt, memoHash);
    }

    /// @notice Cancel an unpaid invoice.
    function cancelInvoice(bytes32 invoiceId) external {
        Invoice storage inv = invoices[invoiceId];
        if (inv.payee == address(0)) revert InvoiceNotFound();
        if (inv.payee != msg.sender) revert Unauthorized();
        if (inv.paid || inv.cancelled) revert InvoiceAlreadySettled();
        inv.cancelled = true;
        emit InvoiceCancelled(invoiceId, msg.sender);
    }

    /// @notice Settle an invoice directly as the payer (requires prior tUSD8 ERC-20 approval).
    function payInvoiceDirect(bytes32 invoiceId) external nonReentrant {
        Invoice storage inv = invoices[invoiceId];
        if (inv.payee == address(0)) revert InvoiceNotFound();
        if (inv.paid || inv.cancelled) revert InvoiceAlreadySettled();
        if (uint64(block.timestamp) > inv.dueAt) revert InvoiceOverdue();

        inv.paid = true;
        inv.paidBy = msg.sender;
        inv.paidAt = uint64(block.timestamp);

        _safeTransferFrom(msg.sender, inv.payee, inv.amount);
        emit InvoicePaid(invoiceId, msg.sender, inv.payee, inv.amount, bytes32(0));
    }

    /// @notice Settle an invoice via a scoped agent session with budget cap, per-tx cap, expiry, and Confirmation of Payee checks.
    function payInvoiceViaSession(bytes32 invoiceId, bytes32 sessionId) external nonReentrant {
        SpendingSession storage s = sessions[sessionId];
        if (s.payer == address(0) || s.revoked) revert SessionInactive();
        if (msg.sender != s.agent && msg.sender != s.payer) revert Unauthorized();
        if (uint64(block.timestamp) > s.expiresAt) revert SessionExpired();

        Invoice storage inv = invoices[invoiceId];
        if (inv.payee == address(0)) revert InvoiceNotFound();
        if (inv.paid || inv.cancelled) revert InvoiceAlreadySettled();
        if (uint64(block.timestamp) > inv.dueAt) revert InvoiceOverdue();

        if (s.requireVerifiedPayee && !payees[inv.payee].active) revert UnverifiedPayee();
        if (inv.amount > s.perTxCap) revert ExceedsPerTxCap();
        if (s.spent + inv.amount > s.maxBudget) revert ExceedsSessionBudget();

        s.spent += inv.amount;
        inv.paid = true;
        inv.paidBy = s.payer;
        inv.paidAt = uint64(block.timestamp);
        inv.paidViaSession = sessionId;

        _safeTransferFrom(s.payer, inv.payee, inv.amount);
        emit InvoicePaid(invoiceId, s.payer, inv.payee, inv.amount, sessionId);
    }

    /// @notice View remaining budget for a scoped spending session.
    function remainingSessionBudget(bytes32 sessionId) external view returns (uint256) {
        SpendingSession storage s = sessions[sessionId];
        if (s.revoked || uint64(block.timestamp) > s.expiresAt || s.spent >= s.maxBudget) {
            return 0;
        }
        return s.maxBudget - s.spent;
    }

    function _safeTransferFrom(address from, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = address(stablecoin).call(
            abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, amount)
        );
        if (!ok || (data.length > 0 && !abi.decode(data, (bool)))) {
            revert TransferFailed();
        }
    }
}
