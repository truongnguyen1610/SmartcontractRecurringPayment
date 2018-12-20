pragma solidity ^0.4.17;

contract Payment {
    enum SubscriptionState {
        PENDING, // State when a subscription first submits
        EXECUTED, // For ONE_TIME payment
        RUNNING, // For INSTALMENT payment which has run at latest one time
        EXPIRED, // For INSTALMENT payment which has reached maxExecutions
        CANCELLED, // Subscription has cancelled before executing
        REGRETTED // State after refund successfully, this is applied for a executed subscription or running subscription
    }
    enum Interval {MONTHLY, QUARTERLY, YEARLY}
    enum PaymentType {ONE_TIME, INSTALMENT}

    struct Date {
        uint year;
        uint month;
        uint day;
    }

    struct Subscription {
        uint balance;
        uint amount;
        PaymentType paymentType;
        SubscriptionState state;
        Interval interval;
        uint executions; // Track how many times the subscription has executed, will expired when executions = maxExecutions
        uint maxExecutions;
        address toAccount;
        Date startAt;
    }

    mapping(address => Subscription) public subscriptions;
    address[] public clientAddresses;
    uint [] daysInMonth;

    constructor() public{
        daysInMonth.push(31);
        daysInMonth.push(28);
        daysInMonth.push(31);
        daysInMonth.push(30);
        daysInMonth.push(31);
        daysInMonth.push(30);
        daysInMonth.push(31);
        daysInMonth.push(31);
        daysInMonth.push(30);
        daysInMonth.push(31);
        daysInMonth.push(30);
        daysInMonth.push(31);
    }
    modifier isActive(SubscriptionState state) {
        require(state == SubscriptionState.PENDING || state == SubscriptionState.RUNNING);

        _;
        // continue executing rest of method body
    }

    // to deposit to balance of a subscription corresponding to msg.sender
    function deposit() payable isActive(subscriptions[msg.sender].state) public returns (bool){
        subscriptions[msg.sender].balance += msg.value;
        clientAddresses.push(msg.sender);
        return true;
    }
    // to withdraw balance of a subscription corresponding to msg.sender if amount <= balance
    function withdraw(uint amount) payable public returns (bool) {
        require(amount <= subscriptions[msg.sender].balance);
        msg.sender.send(amount);
        subscriptions[msg.sender].balance -= amount;
        return true;
    }

    // transfer back balance to client after subscription finished
    function checkAndTransferRemainBalance(Subscription subscription, address client) internal {
        if ((subscription.state == SubscriptionState.EXECUTED || subscription.state == SubscriptionState.EXPIRED)
        && subscription.balance > 0) {
            client.send(subscription.balance);
        }
    }

    // internal method to execute a subscription
    function execute(Subscription storage subscription, address client) isActive(subscription.state) internal returns (bool) {
        uint amount = subscription.amount;
        require(amount <= subscription.balance);

        subscription.toAccount.transfer(amount);
        subscription.balance -= amount;
        subscription.executions += 1;
        if (subscription.paymentType == PaymentType.ONE_TIME) {
            subscription.state = SubscriptionState.EXECUTED;
        }
        if (subscription.paymentType == PaymentType.INSTALMENT) {
            subscription.state = (subscription.executions == subscription.maxExecutions ? SubscriptionState.EXPIRED : SubscriptionState.RUNNING);
        }
        checkAndTransferRemainBalance(subscription, client);
        return true;
    }
    // to execute a running/or pending
    function run(uint16 currentYear, uint8 currentMonth, uint8 currentDay) public returns (bool) {
        uint length = clientAddresses.length;
        for (uint i = 0; i < length; i++) {
            Subscription storage sub = subscriptions[clientAddresses[i]];
            if (sub.startAt.year == currentYear && sub.startAt.month == currentMonth && sub.startAt.day == currentDay) {
                execute(sub, clientAddresses[i]);
                setStartsAt(sub.startAt, sub.interval);
            }
        }
        return true;
    }
    // add new subscription
    function submit(uint amount, uint paymentType, uint interval, uint maxExecutions, address toAccount, uint16 startAtYear, uint8 startAtMonth, uint8 startAtDay) public returns (uint) {
        require(uint(PaymentType.INSTALMENT) >= paymentType);
        require(uint(Interval.YEARLY) >= interval);
        subscriptions[msg.sender] = Subscription(0, amount, PaymentType(paymentType), SubscriptionState.PENDING, Interval(interval), 0, maxExecutions, toAccount, Date(startAtYear, startAtMonth, startAtDay));
        clientAddresses.push(msg.sender);
        return 1;
    }

    // cancel subscription
    function cancel() public returns (bool) {
        require(subscriptions[msg.sender].state == SubscriptionState.PENDING);
        if(subscriptions[msg.sender].balance > 0){
            msg.sender.send(subscriptions[msg.sender].balance);
        }
        subscriptions[msg.sender].state = SubscriptionState.CANCELLED;
        return true;
    }

    function testGet() public view returns (uint, uint, PaymentType, Interval, uint, uint, address, SubscriptionState, uint, uint, uint) {
        Subscription sub = subscriptions[msg.sender];
        return (sub.balance, sub.amount, sub.paymentType, sub.interval, sub.executions, sub.maxExecutions, sub.toAccount, sub.state, sub.startAt.year, sub.startAt.month, sub.startAt.day);
    }

    function setStartsAt(Date storage startAt, Interval interval) internal {
        uint noOfDays = (interval == Interval.MONTHLY ? 30 : interval == Interval.QUARTERLY ? 90 : 365);

        uint d = startAt.day + noOfDays;
        uint m = startAt.month;
        uint y = startAt.year;
        while (d > (daysInMonth[startAt.month - 1])) {
            d = d - (daysInMonth[startAt.month - 1]);
            m++;
            if (m > 12) {
                y++;
                m = 1;
            }
        }
        startAt.day = d;
        startAt.month = m;
        startAt.year = y;
    }
}