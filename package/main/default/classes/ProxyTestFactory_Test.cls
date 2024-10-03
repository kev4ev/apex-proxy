/**
 * @description Test class for ProxyTestFactory functionality.
 * Implements Interfaces.DbRead itself to provide coverage of stub functionalities.
 */
@isTest
public inherited sharing class ProxyTestFactory_Test implements Interfaces.DbRead {
    /***************************************
     * Interfaces.DbRead implementation
     ***************************************/

    public List<SObject> read() {
        return null;
    }

    public void setRetrieveCondition(String condition) {
    }

    public String stubValidator(String validationArg) {
        return validationArg;
    }

    /***************************************
     * Unit tests
     ***************************************/

    @isTest
    private static void coverInterfaces() {
        new Interfaces();
    }

    @isTest
    private static void validateRead_basic() {
        TestDataSet data = new TestDataSet();
        // ensure casting and references work as expected
        Contact c = (Contact) data.accessor.getReader().read()[0];
        Assert.areEqual(data.ct.LastName, c.LastName);
        Assert.areEqual(data.act.Name, c.Account.Name);
        Assert.areEqual(2, c.Tasks.size());
        Assert.areEqual(data.tsk.Subject, c.Tasks.get(0).Subject);
        System.debug('\n' + JSON.serializePretty(c));
    }

    @isTest
    private static void when_mixedSobjecttype_expect_exception() {
        ProxyTestFactory.Reader reader = new TestDataSet()
            .accessor.getReader();
        try {
            reader.addRoot(new Account(Name = 'Shoulda Been a Contact'));
        } catch (ProxyTestFactory.AccessorException ae) {
            Assert.isTrue(true);
        } catch (Exception e) {
            Assert.fail();
        }
    }

    @isTest
    private static void validateReaderAsTestStub() {
        // init reader
        TestDataSet data = new TestDataSet();
        ProxyTestFactory.Reader reader = data.accessor.getReader();
        // mock a concrete implementation
        StubController controller = new StubController();
        ProxyTestFactory_Test stubbed = (ProxyTestFactory_Test) reader.asTestStub(
            ProxyTestFactory_Test.class,
            controller
        );
        // validate that any method other than read() returns the arg passed to it
        String expected = 'validated';
        String actual = stubbed.stubValidator(expected);
        Assert.areEqual(expected, actual);
        Assert.isTrue(controller.called);
        // validate that read() method returns the test reader's sobject list
        List<Contact> contacts = (List<Contact>) stubbed.read();
        Assert.areEqual(1, contacts.size());
    }

    @isTest
    private static void validateReader_conditional() {
        // condition to validate
        String CONDITION = 'conditionA';
        // init reader
        TestDataSet data = new TestDataSet();
        ProxyTestFactory.Reader reader = data.accessor.getReader();
        // mock a concrete implementation
        StubController controller = new StubController();
        ProxyTestFactory_Test stubbed = (ProxyTestFactory_Test) reader.asTestStub(
            ProxyTestFactory_Test.class,
            controller
        );
        // set the condition in the stub and create a list for retrieval
        stubbed.setRetrieveCondition(CONDITION);
        reader.addConditionalRead(new Contact(LastName = CONDITION), CONDITION);
        reader.setReadCondition(CONDITION);
        // read and assert data set returned is the conditional set
        List<Contact> conditionList = (List<Contact>) stubbed.read();
        Assert.areEqual(CONDITION, conditionList.get(0).LastName);
    }

    @isTest
    private static void when_stepNotLooped_expect_null() {
        ProxyTestFactory.Reader reader = getReader();
        Assert.areEqual(1, reader.read().size());
        Assert.areEqual(null, reader.read());
    }

    @isTest
    private static void when_loopedStep_expect_repeatsUntilCancelled() {
        TestDataSet data = new TestDataSet();
        ProxyTestFactory.Reader reader = data.accessor.getReader();
        reader.addReadStep(new Contact(LastName = 'secondStep'));
        // loop result step 0
        reader.loopReadStep(0);
        for (Integer i = 0, k = randomLessThan(10); i < k; i++) {
            Assert.areEqual(
                data.ct.LastName,
                ((Contact) reader.read()[0]).LastName
            );
        }
        reader.cancelLoop();
        Assert.areEqual('secondStep', ((Contact) reader.read()[0]).LastName);
        // now reads are exhausted, expect null
        Assert.areEqual(null, reader.read());
    }

    @isTest
    private static void when_loopedCondition_expect_repeatsUntilCancelled() {
        String CONDITION = 'condition';
        TestDataSet data = new TestDataSet();
        ProxyTestFactory.Reader reader = data.accessor.getReader();
        reader.addReadStep(new Contact(LastName = 'secondStep'));
        reader.addConditionalRead(new Contact(LastName = CONDITION), CONDITION);
        reader.loopReadCondition(CONDITION);
        for (Integer i = 0, k = randomLessThan(10); i < k; i++) {
            assert.areEqual(CONDITION, ((Contact) reader.read()[0]).LastName);
        }
        // cancel the loop and assert steps continue as expected
        reader.cancelLoop();
        Assert.areEqual(data.ct.LastName, getFirstContact(data).LastName);
        Assert.areEqual('secondStep', getFirstContact(data).LastName);
        Assert.areEqual(null, reader.read());
    }

    @isTest
    private static void validateEmptyRead() {
        ProxyTestFactory.Reader reader = ProxyTestFactory.init()
            .getReader();
        reader.addEmptyReadStep();
        Assert.areEqual(0, reader.read().size());
    }

    private static Contact getFirstContact(TestDataSet tds) {
        return ((Contact) tds.accessor.getReader().read()[0]);
    }

    private static Integer randomLessThan(Integer ceiling) {
        Integer rand = (Math.random() * ceiling).round().intValue();

        return rand > 0 ? rand : 1;
    }

    @isTest
    private static void validateVirtualDataWriter() {
        // init empty list for line coverage
        List<Account> records = new List<Account>();
        Interfaces.VirtualWriter writer = new Interfaces.VirtualWriter();
        writer.insertRecords(records);
        writer.upsertRecords(records);
        writer.updateRecords(records);
        writer.deleteRecords(records);
        writer.undeleteRecords(records);
    }

    private static ProxyTestFactory.Reader getReader() {
        return new TestDataSet().accessor.getReader();
    }

    private class TestDataSet {
        public Account act = getTestAccount();
        public Contact ct = getTestContact();
        public Task tsk = getTestTask();
        public ProxyTestFactory.Accessor accessor {
            get {
                if (accessor == null) {
                    accessor = ProxyTestFactory.init();
                    ProxyTestFactory.Reader reader = (ProxyTestFactory.Reader) accessor.getReader();
                    reader.addRoot(ct);
                    reader.relateChild(tsk);
                    reader.relateChild(tsk);
                    reader.relateParent(act, Schema.Contact.AccountId);
                }

                return accessor;
            }
            private set;
        }

        public TestDataSet() {
        }
    }

    private static Account getTestAccount() {
        return new Account(Name = 'TestAccount');
    }
    private static Contact getTestContact() {
        return new Contact(LastName = 'GoodTest');
    }
    private static Task getTestTask() {
        return new Task(Subject = 'Test Task');
    }

    private class StubController implements System.StubProvider {
        public Boolean called = false;
        // track the set condition
        private String condition;
        public StubController() {
        }
        public Object handleMethodCall(
            Object stubbedObject,
            String stubbedMethodName,
            System.Type returnType,
            List<System.Type> listOfParamTypes,
            List<String> listOfParamNames,
            List<Object> listOfArgs
        ) {
            this.called = true;
            if (
                stubbedMethodName.equalsIgnoreCase('read') &&
                (listOfParamNames == null || listOfParamNames.isEmpty())
            ) {
                // last arg will always be the Reader
                ProxyTestFactory.Reader reader = (ProxyTestFactory.Reader) listOfArgs.get(
                    listOfArgs.size() - 1
                );

                // check for conditional
                if (String.isNotBlank(this.condition)) {
                    reader.setReadCondition(this.condition);
                }

                return reader.read();
            }

            if (stubbedMethodName == 'setRetrieveCondition') {
                this.condition = (String) listOfArgs.get(0);
            }

            return listOfArgs.size() > 0 ? listOfArgs[0] : null;
        }
    }

    @isTest
    /**
     * @description Compares runtime performance of creating and querying records in the
     * database versus mocking the result. The db benchmarks will be highly specific to
     * the org in which they are run.
     */
    private static void benchmark() {
        Datetime dbStart, dbEnd;
        Datetime mockStart, mockEnd;
        Integer dbMs, mockMs, diffMs;
        try {
            // db benchmark
            dbStart = Datetime.now();
            insert getTestAccount();
            insert getTestContact();
            insert new List<Task>{ getTestTask(), getTestTask() };
            List<Contact> dbresult = [
                SELECT
                    Id,
                    Name,
                    Account.Id,
                    Account.Name,
                    (SELECT Id, Subject FROM Tasks)
                FROM Contact
            ];
            dbEnd = Datetime.now();
            dbMs = dbEnd.getTime().intValue() - dbStart.getTime().intValue();
            // mock benchmark
            mockStart = Datetime.now();
            ProxyTestFactory.Accessor accessor = ProxyTestFactory.init();
            ProxyTestFactory.Reader reader = (ProxyTestFactory.Reader) accessor.getReader();
            reader.addRoot(getTestContact());
            reader.relateChild(getTestTask());
            reader.relateChild(getTestTask());
            reader.relateParent(getTestAccount(), Schema.Contact.AccountId);
            List<Contact> contacts = (List<Contact>) reader.read();
            mockEnd = Datetime.now();
            mockMs =
                mockEnd.getTime().intValue() - mockStart.getTime().intValue();
            // calculate diff
            diffMs = dbMs - mockMs;
            System.debug(
                System.LoggingLevel.INFO,
                String.format(
                    '\n--------------------\n' +
                        'Benchmark Results' +
                        '\n--------------------\n' +
                        '{0}\n{1}\n{2}*' +
                        '\n--------------------\n*{3}' +
                        '\n--------------------\n' +
                        '--------------------\n',
                    new List<String>{
                        'Db runtime (ms): ' + dbMs,
                        'Mock runtime (ms): ' + mockMs,
                        'Diff (ms): ' + diffMs,
                        'Benchmark results are highly org-specific and influenced by factors including data volume ' +
                        'and the number and complexity of database-triggered automations, sharing rules, etc.'
                    }
                )
            );
        } catch (DmlException e) {
            System.debug(
                System.LoggingLevel.ERROR,
                'Could not perform benchmark test due to DmlException:\n' +
                e.getMessage()
            );
        } catch (Exception e) {
            System.debug(
                System.LoggingLevel.ERROR,
                'Could not perform benchmark test due to unhandled exception:\n' +
                e.getMessage()
            );
        }
    }
}
