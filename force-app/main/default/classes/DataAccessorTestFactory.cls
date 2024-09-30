@isTest
/**
 * @description A factory class for unit tests that need to generate DataAccessor instances. This class includes
 * unit tests for itself at the bottom (tagged with @isTest);
 */
global inherited sharing class DataAccessorTestFactory {
    private static Map<Schema.SObjectType, Integer> recordIdCounter = new Map<Schema.SObjectType, Integer>();

    private static void setId(SObject record) {
        record.Id = getFauxId(record);
    }

    global static String getFauxId(SObject record) {
        Schema.SObjectType sot = record.getSObjectType();
        recordIdCounter.put(sot, (recordIdCounter.get(sot) ?? -1) + 1);
        String pos = recordIdCounter.get(sot).toString();

        String fauxId = String.format(
            '{0}{1}{2}',
            new List<String>{
                sot.getDescribe().getKeyPrefix(),
                pos,
                pos.length() < 12 ? '0'.repeat(12 - pos.length()) : ''
            }
        );

        return fauxId;
    }

    global static DataAccessorTestFactory.Accessor init() {
        return init(null);
    }

    global static DataAccessorTestFactory.Accessor init(Writer writer) {
        writer = writer ?? new Writer();

        return new Accessor(writer);
    }

    global class Accessor implements DataInterfaces.Accessor {
        private Reader reader;
        private Writer writer;

        private Accessor(Writer writer) {
            this.writer = writer;
            this.reader = new Reader();
        }

        global Reader getReader() {
            return this.reader;
        }

        global Writer getWriter() {
            return this.writer;
        }
    }

    global class Reader implements DataInterfaces.Reader {
        // meta
        private Map<Schema.SObjectType, List<Schema.ChildRelationship>> childrenRelMap = new Map<Schema.SObjectType, List<Schema.ChildRelationship>>();
        // records
        private List<List<SObject>> readStepRecords = new List<List<SObject>>{
            new List<SObject>()
        };
        private Map<String, List<SObject>> readConditionalRecords = new Map<String, List<SObject>>();
        private Map<String, ChildRecords> childMap = new Map<String, ChildRecords>();
        // build-time state
        private String buildtimeCondition;
        // read-time (rt) state
        private Integer readtimeReadStep = 0;
        private String readtimeCondition;
        private Boolean freezeReadState = false;
        /** @description A callback controller that will be invoked when Reader is used as a Test stub */
        private System.StubProvider controller;
        /** @constructor */
        private Reader() {
        }

        /********************
         * READ-TIME METHODS
         ********************/

        global List<SObject> read() {
            List<SObject> readList;
            // read either from current conditional list or step list
            if (String.isNotBlank(this.readtimeCondition)) {
                readList = this.readConditionalRecords.get(
                    this.readtimeCondition
                );
                if (!freezeReadState) {
                    this.readtimeCondition = null;
                }
            } else {
                // return the list or null if read steps exhausted
                readList = readtimeReadStep < this.readStepRecords.size()
                    ? this.readStepRecords.get(this.readtimeReadStep)
                    : null;
                if (!freezeReadState) {
                    this.readtimeReadStep += 1;
                }
            }

            // return the results
            return readList;
        }

        global Reader loopReadStep(Integer step) {
            this.freezeReadState = true;
            Integer max = readStepRecords.size() - 1;
            if (step > max) {
                throw new AccessorException(
                    'Index out of bounds: ' +
                        step.toString() +
                        '; max size is ' +
                        max
                );
            }
            this.readtimeReadStep = step;

            return this;
        }

        global Reader setReadCondition(String condition) {
            if (!this.readConditionalRecords.keySet().contains(condition)) {
                throw new AccessorException(
                    'Condition ' +
                        condition +
                        ' was never initialized. Use addConditionalRead().'
                );
            }
            this.readtimeCondition = condition;

            return this;
        }

        global Reader loopReadCondition(String condition) {
            this.freezeReadState = false;

            return setReadCondition(condition);
        }

        /********************
         * BUILD-TIME METHODS
         ********************/

        /**
         * Adds a read step that will return a list of records of size 0.
         * @return {Reader} the reader instance for chaining
         */
        global Reader addEmptyReadStep() {
            Integer addNew = getBuildtimeStepRecords().isEmpty() ? 1 : 2;
            for (Integer i = 0, k = addNew; i < k; i++) {
                this.readStepRecords.add(new List<SObject>());
            }

            return this;
        }

        /**
         * Add a new read step to the Reader.
         * @param {SObject} record the root record to initizize the new read step list
         * @return {Reader} the reader instance for chaining
         */
        global Reader addReadStep(SObject record) {
            // ensure current list is not empty
            if (getBuildtimeStepRecords().isEmpty()) {
                throw new AccessorException(
                    'Current read step record list is empty. ' +
                        'You may not add a new read step while the current one is empty. If you want to add ' +
                        'an empty read step, use addEmptyRead().'
                );
            }
            this.readStepRecords.add(new List<SObject>());
            this.buildtimeCondition = null;

            return record == null ? this : addRoot(record);
        }

        /**
         * Add a new read step to the Reader.
         * @param {SObject} record the root record to initizize the new read step list
         * @param {String} condition the condition that must be set for the record list to return; use
         * setReadCondition() to enable the condition
         * @return {Reader} the reader instance for chaining
         */
        global Reader addConditionalRead(SObject record, String condition) {
            this.readConditionalRecords.put(condition, new List<SObject>());
            this.buildtimeCondition = condition;

            return addRoot(record);
        }

        private List<SObject> getCurrentBuildtimeRecords() {
            return String.isNotBlank(this.buildtimeCondition)
                ? this.readConditionalRecords.get(this.buildtimeCondition)
                : getBuildtimeStepRecords();
        }

        private List<SObject> getBuildtimeStepRecords() {
            return this.readStepRecords.get(this.readStepRecords.size() - 1);
        }

        /**
         * Add a record to the current read list.
         * @param {SObject} record the record to add
         * @return {Reader} this instance for chaining
         */
        global Reader addRoot(SObject record) {
            // set a faux id
            setId(record);
            // get the list to append record
            List<SObject> appendTo = getCurrentBuildtimeRecords();
            // ensure sobjecttype list equality
            Schema.SObjectType currentBuildType = appendTo.isEmpty()
                ? null
                : appendTo.get(0).getSObjectType();
            Schema.SObjectType recordSobjectType = record.getSObjectType();
            if (
                currentBuildType != null &&
                currentBuildType != recordSobjectType
            ) {
                throw new AccessorException(
                    String.format(
                        'Current list\'s sobjectTYpe is "{0}" but record is of type "{1}.' +
                            '\nA list can only return records of the same sobjecttype.' +
                            '\n Add a new step to return records of a new sobjecttype',
                        new List<String>{
                            currentBuildType.getDescribe().getName(),
                            recordSobjectType.getDescribe().getName()
                        }
                    )
                );
            }
            // conditionally add child meta
            if (!this.childrenRelMap.containsKey(recordSobjectType)) {
                this.childrenRelMap.put(
                    recordSobjectType,
                    recordSobjectType.getDescribe().getChildRelationships()
                );
            }
            // add the record and return self
            appendTo.add(record);

            return this;
        }

        global Reader relateParent(SObject parent, Schema.SObjectField field) {
            return relateParent(
                parent,
                field,
                getCurrentBuildtimeRecords().size() - 1
            );
        }

        global Reader relateParent(
            SObject parent,
            Schema.SObjectField field,
            Integer rootRecordPosition
        ) {
            // set faux id
            setId(parent);
            // normalize relationship name
            String rawName = field.getDescribe().getName();
            String relName = rawName.endsWith('__c')
                ? rawName.replace('__c', '__r')
                : rawName.replace('Id', '');
            // delegate field set and return self
            setRootFieldDynamic(rootRecordPosition, relName, parent);

            return this;
        }

        global Reader relateChild(SObject child) {
            return relateChild(child, getCurrentBuildtimeRecords().size() - 1);
        }

        global Reader relateChild(SObject child, Integer rootRecordPosition) {
            // set faux id
            setId(child);
            // find the relationship name
            SObject parent = getCurrentBuildtimeRecords()
                .get(rootRecordPosition);
            Schema.SObjectType parentType = parent.getSObjectType();
            Schema.SObjectType childType = child.getSObjectType();
            String relationshipName;
            for (
                Schema.ChildRelationship rel : this.childrenRelMap.get(
                    parentType
                )
            ) {
                if (rel.getChildSObject() == childType) {
                    relationshipName = rel.getRelationshipName();

                    break;
                }
            }
            // throw if invalid relationship
            if (String.isBlank(relationshipName)) {
                throw new AccessorException(
                    childType.getDescribe().getName() +
                        ' is not a valid child of ' +
                        parentType.getDescribe().getName()
                );
            }

            // get or init ChildRecords by faux id of the parent
            String fauxParentId = getCurrentBuildtimeRecords()
                .get(rootRecordPosition)
                .Id;
            ChildRecords children = this.childMap.get(fauxParentId);
            if (children == null) {
                children = new ChildRecords();
                childMap.put(fauxParentId, children);
            }
            children.add(child);
            // delegate field set and return self
            setRootFieldDynamic(rootRecordPosition, relationshipName, children);

            return this;
        }

        private void setRootFieldDynamic(
            Integer rootRecordPosition,
            String fieldKey,
            Object fieldValue
        ) {
            // serialize and deserialize
            List<SObject> records = getCurrentBuildtimeRecords();
            SObject root = records.get(rootRecordPosition);
            Map<String, Object> rootMap = (Map<String, Object>) JSON.deserializeUntyped(
                JSON.serialize(root)
            );
            rootMap.put(fieldKey, fieldValue);
            // replace
            SObject newRoot = (SObject) JSON.deserialize(
                JSON.serialize(rootMap),
                SObject.class
            );
            // reset the record in the correct buildtime position
            records[rootRecordPosition] = newRoot;
        }

        global Object asTestStub(
            System.Type concreteReaderType,
            System.StubProvider controller
        ) {
            return Test.createStub(
                concreteReaderType,
                new StubWrapper(this, controller)
            );
        }
    }

    global class Writer extends DataWriterBase {
        private Writer() {
            super();
        }

        global override List<Database.SaveResult> insertRecords(
            List<SObject> records
        ) {
            // do nothing
            return null;
        }

        global override List<Database.SaveResult> updateRecords(
            List<SObject> records
        ) {
            // do nothing
            return null;
        }

        global override List<Database.UpsertResult> upsertRecords(
            List<SObject> records
        ) {
            // do nothing
            return null;
        }

        global override List<Database.DeleteResult> deleteRecords(
            List<SObject> records
        ) {
            // do nothing
            return null;
        }

        global override List<Database.UndeleteResult> undeleteRecords(
            List<SObject> records
        ) {
            // do nothing
            return null;
        }
    }

    private class StubWrapper implements System.StubProvider {
        private Reader reader;
        private System.StubProvider controller;
        public StubWrapper(Reader reader, System.StubProvider controller) {
            this.reader = reader;
            this.controller = controller;
        }

        public Object handleMethodCall(
            Object stubbedObject,
            String stubbedMethodName,
            System.Type returnType,
            List<System.Type> listOfParamTypes,
            List<String> listOfParamNames,
            List<Object> listOfArgs
        ) {
            // pass through to controller
            return controller.handleMethodCall(
                stubbedObject,
                stubbedMethodName,
                returnType,
                listOfParamTypes,
                listOfParamNames,
                listOfArgs
            );
        }
    }

    private class ChildRecords {
        public Integer totalSize = 0;
        public Boolean done = true;
        public List<SObject> records = new List<SObject>();
        /** @constructor */
        public ChildRecords() {
        }

        public void add(SObject child) {
            this.records.add(child);
            this.totalSize = this.records.size();
        }
    }

    private class AccessorException extends Exception {
    }

    private class StubController implements System.StubProvider {
        public Boolean called = false;
        private Reader reader;
        public StubController(Reader reader) {
            this.reader = reader;
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
                listOfArgs.isEmpty()
            ) {
                return reader.read();
            }

            return listOfArgs.size() > 0 ? listOfArgs[0] : null;
        }
    }

    @isTest
    private static void coverDataInterfaces() {
        new DataInterfaces();
    }

    @isTest
    private static void validateReadOperations() {
        Account act = getTestAccount();
        Contact ct = getTestContact();
        Task t = getTestTask();
        Accessor accessor = init();
        Reader reader = (Reader) accessor.getReader();
        reader.addRoot(ct);
        reader.relateChild(t);
        reader.relateChild(t);
        reader.relateParent(act, Schema.Contact.AccountId);
        // ensure casting and references work as expected
        Contact c = (Contact) reader.read()[0];
        Assert.areEqual(ct.LastName, c.LastName);
        Assert.areEqual(act.Name, c.Account.Name);
        Assert.areEqual(2, c.Tasks.size());
        Assert.areEqual(t.Subject, c.Tasks.get(0).Subject);
        System.debug('\n' + JSON.serializePretty(c));
    }

    @isTest
    private static void validateReaderAsTestStub() {
        // init reader
        Accessor accessor = init();
        Reader reader = (Reader) accessor.getReader();
        Contact ct = getTestContact();
        reader.addRoot(ct);
        reader.relateChild(getTestTask());
        reader.relateChild(getTestTask());
        reader.relateParent(getTestAccount(), Schema.Contact.AccountId);
        // mock a concrete implementation
        StubController controller = new StubController(reader);
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
            Accessor accessor = init();
            Reader reader = (Reader) accessor.getReader();
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

    private static Account getTestAccount() {
        return new Account(Name = 'TestAccount');
    }
    private static Contact getTestContact() {
        return new Contact(LastName = 'GoodTest');
    }
    private static Task getTestTask() {
        return new Task(Subject = 'Test Task');
    }
}
