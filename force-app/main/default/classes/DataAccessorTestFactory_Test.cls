@isTest
private inherited sharing class DataAccessorTestFactory_Test {
    @isTest
    private static void coverDataInterfaces() {
        new DataInterfaces();
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
        DataAccessorTestFactory.Reader reader = new TestDataSet()
            .accessor.getReader();
        try {
            reader.addRoot(new Account(Name = 'Shoulda Been a Contact'));
        } catch (DataAccessorTestFactory.AccessorException ae) {
            Assert.isTrue(true);
        } catch (Exception e) {
            Assert.fail();
        }
    }

    @isTest
    private static void validateReaderAsTestStub() {
        // init reader
        TestDataSet data = new TestDataSet();
        DataAccessorTestFactory.Reader reader = data.accessor.getReader();
        // mock a concrete implementation
        StubController controller = new StubController();
        DataReaderTestStub stubbed = (DataReaderTestStub) reader.asTestStub(
            DataReaderTestStub.class,
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
        DataAccessorTestFactory.Reader reader = data.accessor.getReader();
        // mock a concrete implementation
        StubController controller = new StubController();
        DataReaderTestStub stubbed = (DataReaderTestStub) reader.asTestStub(
            DataReaderTestStub.class,
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
    private static void validateDataWriterBase() {
        // init empty list for line coverage
        List<Account> records = new List<Account>();
        DataWriterBase writer = new DataWriterBase();
        writer.insertRecords(records);
        writer.upsertRecords(records);
        writer.updateRecords(records);
        writer.deleteRecords(records);
        writer.undeleteRecords(records);
    }

    private class TestDataSet {
        public Account act = getTestAccount();
        public Contact ct = getTestContact();
        public Task tsk = getTestTask();
        public DataAccessorTestFactory.Accessor accessor {
            get {
                if (accessor == null) {
                    accessor = DataAccessorTestFactory.init();
                    DataAccessorTestFactory.Reader reader = (DataAccessorTestFactory.Reader) accessor.getReader();
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
                DataAccessorTestFactory.Reader reader = (DataAccessorTestFactory.Reader) listOfArgs.get(
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
            DataAccessorTestFactory.Accessor accessor = DataAccessorTestFactory.init();
            DataAccessorTestFactory.Reader reader = (DataAccessorTestFactory.Reader) accessor.getReader();
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
