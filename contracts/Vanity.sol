// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "./Context.sol";

contract Vanity is Context {
    struct Registration {
        address user;
        string name;
        uint256 creation;
        uint256 expiration;
        uint256 amount;
    }
    struct Reservation {
        address user;
        uint256 expiration;
    }

    mapping(bytes32 => Registration) public _registrations;
    mapping(address => bytes32[]) public _userLookup;
    mapping(bytes32 => Reservation) public _reservations;
    mapping(bytes32 => uint256) public _advances;
    uint256 _lockingAmount = 20;
    uint256 _advance = _lockingAmount / 2;
    uint256 _lockingPeriod = 10 seconds; //365 days;
    uint256 _renewPeriod = 5 seconds; //5 days;
    uint256 _basePrice = 1;
    uint256 _cancellationFee = 1;
    uint256 _reservationPeriod = 5 seconds; //1 days;

    /**
     * @dev Allows user which has previously reserved `Registration` using `registrationId` to buy
     * `name` for `_lockingPeriod` of time. Method accepts  payment with amount of `_advance` plus fee.
     */
    function buy(bytes32 registrationId, string memory name)
        external
        payable
        returns (bytes32, Registration memory)
    {
        require(
            _reservationValid(registrationId),
            "Reservation doesn't exists"
        );
        require(registrationId == _createRegistrationId(name));
        require(
            _reservations[registrationId].user == address(_msgSender()),
            "Access not allowed"
        );

        uint256 advance = _advances[registrationId];
        uint256 payed = _msgValue() + advance;
        uint256 toPay = _lockingAmount + calculateFee(name);
        require(payed >= toPay, "Insufficient amount");
        if (
            _registrations[registrationId].user != address(0) &&
            block.timestamp >= _registrations[registrationId].expiration
        ) {
            Registration memory oldRegistration = _registrations[
                registrationId
            ];
            address payable receiver = payable(oldRegistration.user);
            _cleanRegistration(receiver, registrationId);
            if (oldRegistration.amount > 0) {
                receiver.transfer(oldRegistration.amount);
            }
        }
        Registration memory registration = _createRegistration(
            name,
            block.timestamp
        );
        _registrations[registrationId] = registration;
        _userLookup[_msgSender()].push(registrationId);
        delete _reservations[registrationId];
        delete _advances[registrationId];
        emit Bought(_msgSender(), name, registration.expiration);
        if (payed > _lockingAmount) {
            _msgSender().transfer(payed - toPay);
        }
        return (registrationId, registration);
    }

    /**
     * @dev Factory method for `Registration`.
     */
    function _createRegistration(string memory name, uint256 startTimestamp)
        internal
        view
        returns (Registration memory)
    {
        return
            Registration(
                _msgSender(),
                name,
                startTimestamp,
                startTimestamp + _lockingPeriod,
                _lockingAmount
            );
    }

    /**
     * @dev Allows `_msgSender()` to renew already bought `Registration` for `name`.
     * Renewals is available `_renewPeriod` before Registration expiration.
     */
    function renew(string memory name) external returns (bool) {
        bytes32 registrationId = _createRegistrationId(name);
        Registration memory registration = _registrations[registrationId];
        require(
            registration.user == address(_msgSender()),
            "Access not allowed"
        );
        require(
            (block.timestamp + _renewPeriod) >= registration.expiration,
            "Not allowed yet."
        );
        _registrations[registrationId] = _createRegistration(
            name,
            registration.expiration
        );
        emit Renewed(
            _msgSender(),
            name,
            registration.expiration + _lockingPeriod
        );
        return true;
    }

    /**
     * @dev Claims `_lockingAmount` amount which is locked during the buy.
     * Frees registration of `name` so it can be used again.
     */
    function claim(string memory name) external returns (bool) {
        bytes32 registrationId = _createRegistrationId(name);
        Registration memory registration = _registrations[registrationId];
        require(
            registration.user == address(_msgSender()),
            "Access not allowed"
        );
        require(block.timestamp >= registration.expiration, "Not allowed yet.");
        _cleanRegistration(_msgSender(), registrationId);
        emit Claimed(_msgSender(), name);
        _msgSender().transfer(registration.amount);
        return true;
    }

    /**
     * @dev Removes registration from `_registrations` and `_userLookup`.
     */
    function _cleanRegistration(address addr, bytes32 registrationId)
        internal
        returns (Registration memory)
    {
        delete _registrations[registrationId];
        bytes32[] memory lookup = _userLookup[addr];
        uint256 index = lookup.length - 1;
        for (uint256 i = 0; i < lookup.length; i++) {
            if (lookup[i] == registrationId) {
                index = i;
                break;
            }
        }
        bytes32 tmp = lookup[lookup.length - 1];
        _userLookup[addr][lookup.length - 1] = registrationId;
        _userLookup[addr][index] = tmp;
        _userLookup[addr].pop();
        return _registrations[registrationId];
    }

    /**
     * @dev Derives `registrationId` from `name`, returns bytes32 hash.
     */
    function _createRegistrationId(string memory name)
        internal
        view
        returns (bytes32)
    {
        return keccak256(abi.encode(address(this), name));
    }

    /**
     * @dev Reserves registration identified with `registrationId` which is derived from `name`.
     * Accepts as value `_advance`. Reservation last for `_reservationPeriod` period of time.
     * If prior registration with same `registrationId` which `_reservationPeriod` is expired is fount it is canceled.
     */
    function reserve(bytes32 registrationId) external payable returns (bool) {
        require(!_reservationValid(registrationId), "Reservation exists");
        require(_msgValue() == _advance, "Invalid amount");
        if (
            _reservations[registrationId].user != address(0) &&
            _reservations[registrationId].expiration > 0
        ) {
            _cancelReservation(
                registrationId,
                _reservations[registrationId].user
            );
        }
        _reservations[registrationId] = Reservation(
            _msgSender(),
            block.timestamp + _reservationPeriod
        );
        _advances[registrationId] = _msgValue();
        emit Reserved(
            _msgSender(),
            registrationId,
            block.timestamp + _reservationPeriod
        );
        return true;
    }

    /**
     * @dev Cancels `registrationId` and returns `advance` amount minus `_cancellationFee`.
     * `_msgSender()` must be owner of reservation.
     */
    function cancelReservation(bytes32 registrationId) public returns (bool) {
        require(
            _reservations[registrationId].user == address(_msgSender()),
            "Access not allowed"
        );
        return _cancelReservation(registrationId, _msgSender());
    }

    /**
     * @dev Cancels `registrationId` and returns `advance` amount minus `_cancellationFee`.
     */
    function _cancelReservation(bytes32 registrationId, address addr)
        internal
        returns (bool)
    {
        uint256 toPay = _advances[registrationId] - _cancellationFee;
        delete _advances[registrationId];
        delete _reservations[registrationId];
        address payable receiver = payable(addr);
        emit ReservationCanceled(registrationId);
        receiver.transfer(toPay);
        return true;
    }

    /**
     * @dev Utility function which checks validity of reservationId.
     */
    function _reservationValid(bytes32 registrationId)
        internal
        view
        returns (bool)
    {
        return
            _reservations[registrationId].user != address(0) &&
            block.timestamp < _reservations[registrationId].expiration;
    }

    /**
     * @dev Creates `registrationId` from `name`,
     returns bytes32.
     */
    function getReservationId(string memory name)
        external
        view
        returns (bytes32)
    {
        require(isAvailableByValue(name), "Not available");
        return _createRegistrationId(name);
    }

    /**
     * @dev Checks if `registrationId` which is derived from `name` is available for registration.
     */
    function isAvailableById(bytes32 registrationId)
        public
        view
        returns (bool)
    {
        return
            _registrations[registrationId].user == address(0) ||
            block.timestamp >= _registrations[registrationId].expiration;
    }

    /**
     * @dev Checks if `name` is available for registration.
     */
    function isAvailableByValue(string memory name) public view returns (bool) {
        bytes32 registrationId = _createRegistrationId(name);
        return isAvailableById(registrationId);
    }

    /**
     * @dev Calculates fee based on `_basePrice` and `name` length,
     returns `uint256`.
     */
    function calculateFee(string memory name) public view returns (uint256) {
        bytes memory b = abi.encodePacked(name);
        return b.length * _basePrice;
    }

    /**
     * @dev Getter for `_lockingAmount`.
     */
    function getLockingAmount() public view returns (uint256) {
        return _lockingAmount;
    }

    /**
     * @dev Getter for `_advance`.
     */
    function getAdvance() public view returns (uint256) {
        return _advance;
    }

    /**
     * @dev Getter for `_lockingPeriod`.
     */
    function getLockingPeriod() public view returns (uint256) {
        return _lockingPeriod;
    }

    /**
     * @dev Getter for `_renewPeriod`.
     */
    function getRenewPeriod() public view returns (uint256) {
        return _renewPeriod;
    }

    /**
     * @dev Getter for `_basePrice`.
     */
    function getBasePrice() public view returns (uint256) {
        return _basePrice;
    }

    /**
     * @dev It is emitted when `name` is bought.
     */
    event Bought(address indexed addr, string name, uint256 expiration);
    /**
     * @dev It is emitted when `id` is reserved.
     */
    event Reserved(address indexed addr, bytes32 id, uint256 expiration);
    /**
     * @dev It is emitted when  reservation with `id` is canceled.
     */
    event ReservationCanceled(bytes32 id);
    /**
     * @dev It is emitted when  `name` is renewed.
     */
    event Renewed(address indexed addr, string name, uint256 expiration);
    /**
     * @dev It is emitted when amount locked for `name` is claimed.
     */
    event Claimed(address indexed addr, string name);
}
