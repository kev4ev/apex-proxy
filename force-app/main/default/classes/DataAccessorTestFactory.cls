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

    global static DataAccessorTestFactory.Accessor init(
        Schema.SObjectType sobjectType
    ) {
        return init(sobjectType, null);
    }

    global static DataAccessorTestFactory.Accessor init(
        Schema.SObjectType sobjectType,
        Writer writer
    ) {
        writer = writer ?? new Writer(sobjectType);

        return new Accessor(sobjectType, writer);
    }

    global class Accessor implements DataInterfaces.Accessor {
        private Schema.SObjectType sobjectType;
        private Reader reader;
        private Writer writer;

        private Accessor(Schema.SObjectType sobjectType, Writer writer) {
            this.sobjectType = sobjectType;
            this.writer = writer;
            this.reader = new Reader(sobjectType);
        }

        global Reader getReader() {
            return this.reader;
        }

        global Writer getWriter() {
            return this.writer;
        }
    }

    global class Reader implements DataInterfaces.Reader {
        private List<SObject> records = new List<SObject>();
        private Schema.SObjectType sobjectType;
        private String sobjectTypeString;
        private List<Schema.ChildRelationship> children;
        // more performant than round-trip serialization / deserialization
        private Map<Integer, ChildRecords> childMap = new Map<Integer, ChildRecords>();
        /** @constructor */
        private Reader(Schema.SObjectType sobjectType) {
            this.sobjectType = sobjectType;
            this.sobjectTypeString = sobjectType.getDescribe().getName();
            this.children = sobjectType.getDescribe().getChildRelationships();
        }

        global Schema.SObjectType handlesType() {
            return this.sobjectType;
        }

        global List<SObject> read() {
            return this.records;
        }

        global Reader addRoot(SObject record) {
            setId(record);
            Schema.SObjectType recordSObjectType = record.getSObjectType();
            if (recordSObjectType != this.sobjectType) {
                throw new AccessorException(
                    String.format(
                        'Accessor\'s root SObjectType is {0} but record\'s type is {1}',
                        new List<String>{
                            sobjectTypeString,
                            recordSObjectType.getDescribe().getName()
                        }
                    )
                );
            }

            this.records.add(record);

            return this;
        }

        global Reader relateParent(SObject parent, Schema.SObjectField field) {
            return relateParent(parent, field, this.records.size() - 1);
        }

        global Reader relateParent(
            SObject parent,
            Schema.SObjectField field,
            Integer rootRecordPosition
        ) {
            setId(parent);
            String rawName = field.getDescribe().getName();
            String relName = rawName.endsWith('__c')
                ? rawName.replace('__c', '__r')
                : rawName.replace('Id', '');
            setRootFieldDynamic(rootRecordPosition, relName, parent);
            return this;
        }

        global Reader relateChild(SObject child) {
            return relateChild(child, this.records.size() - 1);
        }

        global Reader relateChild(SObject child, Integer rootRecordPosition) {
            setId(child);
            Schema.SObjectType childType = child.getSObjectType();
            String relationshipName;
            for (Schema.ChildRelationship rel : this.children) {
                if (rel.getChildSObject() == childType) {
                    relationshipName = rel.getRelationshipName();

                    break;
                }
            }
            if (String.isBlank(relationshipName)) {
                throw new AccessorException(
                    childType.getDescribe().getName() +
                        ' is not a valid child of ' +
                        sobjectTypeString
                );
            }

            // get or init ChildRecords
            ChildRecords children = this.childMap.get(rootRecordPosition);
            if (children == null) {
                children = new ChildRecords();
                childMap.put(rootRecordPosition, children);
            }
            children.add(child);

            setRootFieldDynamic(rootRecordPosition, relationshipName, children);

            return this;
        }

        private void setRootFieldDynamic(
            Integer rootRecordPosition,
            String fieldKey,
            Object fieldValue
        ) {
            // serialize and deserialize
            SObject root = this.records.get(rootRecordPosition);
            Map<String, Object> rootMap = (Map<String, Object>) JSON.deserializeUntyped(
                JSON.serialize(root)
            );
            rootMap.put(fieldKey, fieldValue);
            // replace
            SObject newRoot = (SObject) JSON.deserialize(
                JSON.serialize(rootMap),
                SObject.class
            );
            this.records[rootRecordPosition] = newRoot;
        }
    }

    global class Writer extends DataWriterBase {
        private Writer(Schema.SObjectType sobjectType) {
            super(sobjectType);
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

    @isTest
    private static void validateReadOperations() {
        Account act = getTestAccount();
        Contact ct = getTestContact();
        Task t = getTestTask();
        Accessor accessor = init(Schema.Contact.getSObjectType());
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
    private static void validateDataWriterBase() {
        // init empty list for line coverage
        List<Account> records = new List<Account>();
        Schema.SObjectType actType = Schema.Account.getSObjectType();
        DataWriterBase writer = new DataWriterBase(actType);
        Assert.areEqual(actType, writer.handlesTypes()[0]);
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
            Accessor accessor = init(Schema.Contact.getSObjectType());
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

    @isTest
    private static void coverDataInterfaces() {
        new DataInterfaces();
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
