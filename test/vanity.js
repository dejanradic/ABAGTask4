const Vanity = artifacts.require("Vanity");

/*
 * uncomment accounts to access the test accounts made available by the
 * Ethereum client
 * See docs: https://www.trufflesuite.com/docs/truffle/testing/writing-tests-in-javascript
 */
contract("Vanity", function(accounts) {
    let instance;
    let name = "a1234567890Ћž";
    let name2 = "a1234567890";
    let name3 = "a1234567890Za2";
    let advance;
    let fullAmount;
    let ticket;
    let ticket2;
    let ticket3
    let lockingPeriod;
    let renewPeriod;

    describe('Calculations', async() => {
        before(async() => {
            instance = await Vanity.deployed();
        });
        it('should be equals to 4x and 6x from basePrice', async() => {
            let nameAsci = "t123";
            let nameUtf8 = "a1Ћž";
            let basePrice = await instance.getBasePrice.call();
            let fee = await instance.calculateFee.call(nameAsci);
            assert.equal(fee, basePrice * 4);
            fee = await instance.calculateFee.call(nameUtf8);
            assert.equal(fee, basePrice * 6);
        });
    });
    describe('Reservations', async() => {
        before(async() => {
            instance = await Vanity.deployed();
            advance = await instance.getAdvance.call();
            fullAmount = await instance.getLockingAmount.call();
        });
        it('should return reservations', async() => {
            ticket = await instance.getReservationId.call(name);
            assert.equal(ticket.length, 66);
            ticket2 = await instance.getReservationId.call(name2, { from: accounts[1] });
            assert.equal(ticket2.length, 66);
        });
        it('should reserve', async() => {
            ticket = await instance.getReservationId.call(name);
            await instance.reserve(ticket, { value: advance });
        });
        it('should fail with Reservation exists', async() => {
            try {
                await instance.reserve(ticket, { value: advance });
                assert.fail(true, false, "Didn't throw.");
            } catch (error) {
                assert.isTrue(String(error).includes("Reservation exists"));
            }
        });
        it('should buy a ticket', async() => {
            let fee = await instance.calculateFee.call(name);
            try {
                await instance.buy(ticket, name, { value: advance + fee });
            } catch (error) {
                if (String(error).includes("doesn't exists")) {
                    await instance.reserve(ticket, { value: advance });
                    await instance.buy(ticket, name, { value: advance + fee });
                } else {
                    throw error;
                }
            }
        });
        it('should fail claim with Not allowed yet', async() => {
            try {
                await instance.claim(name);
                assert.fail(true, false, "Didn't throw.");
            } catch (error) {
                assert.isTrue(String(error).includes("Not allowed yet"));
            }
        });
        it('should fail claim with Access not allowed', async() => {
            try {
                await instance.claim(name, { from: accounts[1] });
                assert.fail(true, false, "Didn't throw.");
            } catch (error) {
                assert.isTrue(String(error).includes("Access not allowed"));
            }
        });
    });
    describe('Renew and claim', async() => {
        before(async() => {
            instance = await Vanity.deployed();
            advance = await instance.getAdvance.call();
            fullAmount = await instance.getLockingAmount.call();
            lockingPeriod = await instance.getLockingPeriod.call();
            lockingPeriod = lockingPeriod.toNumber();
            renewPeriod = await instance.getRenewPeriod.call();
            renewPeriod = renewPeriod.toNumber();
        });
        it('should successfully renew', async() => {
            let fee = await instance.calculateFee.call(name2);
            ticket2 = await instance.getReservationId.call(name2, { from: accounts[1] });
            await instance.reserve(ticket2, { value: advance, from: accounts[1] });
            await instance.buy(ticket2, name2, { value: advance + fee, from: accounts[1] });
            const wait = 1000 * (1 + lockingPeriod - renewPeriod);
            await new Promise(r => setTimeout(r, wait));
            await instance.renew(name2, { from: accounts[1] });
        });
        it('should successfully claim', async() => {
            let fee = await instance.calculateFee.call(name3);
            ticket3 = await instance.getReservationId.call(name3, { from: accounts[2] });
            await instance.reserve(ticket3, { value: advance, from: accounts[2] });
            await instance.buy(ticket3, name3, { value: advance + fee, from: accounts[2] });
            const wait = 1000 * (lockingPeriod);
            await new Promise(r => setTimeout(r, wait));
            await instance.claim(name3, { from: accounts[2] });
        });
    });
});