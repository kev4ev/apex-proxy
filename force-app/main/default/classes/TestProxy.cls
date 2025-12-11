/**
 * @description Use to intercept calls to Proxy singleton APIs (.db, .reflect()) for mocking during unit tests.
 * Inner base class is necessary as isTest classes cannot be abstract or virtual.
 *
 * Provided under the MIT License github.com/kev4ev/apex-proxy
 */

@isTest
public inherited sharing class TestProxy {
    private static Map<Schema.SObjectType, Integer> recordIdCounter = new Map<Schema.SObjectType, Integer>();

    /******************************
     * STATIC HELPER APIs
     ******************************/

    /**
     * @description Mock the Proxy.singleton with the caller's implementation. Convenience method only
     * as caller could set Proxy.singleton manually.
     */
    public static Base mockSingleton(Base singletonMock) {
        Proxy.singleton = singletonMock;

        return singletonMock;
    }

    /**
     * @description set a a fake Id on an SObject and return it
     */
    public static SObject setFauxId(SObject record) {
        record.Id = getFauxId(record);

        return record;
    }

    /**
     * @description get a fake Id for an SObject but do not update the SObject itself
     */
    public static String getFauxId(SObject record) {
        return getFauxId(record.getSObjectType());
    }

    /**
     * @description get a fake Id for an SObjectType
     */
    public static String getFauxId(Schema.SObjectType sot) {
        if (!recordIdCounter.containsKey(sot)) {
            recordIdCounter.put(sot, -1);
        }
        Integer pos = recordIdCounter.get(sot) + 1;
        recordIdCounter.put(sot, pos);

        String posStr = pos.toString();
        String fauxId = String.format(
            '{0}{1}{2}',
            new List<String>{
                sot.getDescribe().getKeyPrefix(),
                posStr.length() < 12 ? '0'.repeat(12 - posStr.length()) : '',
                posStr
            }
        );

        return fauxId;
    }

    /**
     * @description Base class to extend to mock db calls during unit testing.
     */
    public virtual class Base extends Proxy {
        /******************************************************************
         * REFLECT API OVERRIDE - allows extending test class to implement
         ******************************************************************/

        public virtual override Object trap(Object value, String key) {
            return value;
        }

        /******************************************************************
         * READER API OVERRIDE - allows extending class to implement
         ******************************************************************/

        public virtual override List<SObject> read(
            DbReader reader,
            Object readContext
        ) {
            return reader.read(readContext);
        }

        /******************************************************************
         * WRITE API OVERRIDE - allows extending class to override
         ******************************************************************/

        /** @description overridable; default implementation returns an empty list matching the size of records */
        public virtual override List<Database.SaveResult> insertRecords(
            List<SObject> records
        ) {
            return new List<Database.SaveResult>(records.size());
        }

        /** @description overridable; default implementation returns an empty list matching the size of records */
        public virtual override List<Database.SaveResult> updateRecords(
            List<SObject> records
        ) {
            return new List<Database.SaveResult>(records.size());
        }

        /** @description overridable; default implementation returns an empty list matching the size of records */
        public virtual override List<Database.UpsertResult> upsertRecords(
            List<SObject> records
        ) {
            return new List<Database.UpsertResult>(records.size());
        }

        /** @description overridable; default implementation returns an empty list matching the size of records */
        public virtual override List<Database.DeleteResult> deleteRecords(
            List<SObject> records
        ) {
            return new List<Database.DeleteResult>(records.size());
        }

        /** @description overridable; default implementation returns an empty list matching the size of records */
        public virtual override List<Database.UndeleteResult> undeleteRecords(
            List<SObject> records
        ) {
            return new List<Database.UndeleteResult>(records.size());
        }
    }

    /**
     * @description Provides powerful API for constructing mock SOQL responses
     * including child and parent records.
     */
    public class MockReader {
        /**************************************************
         * READER API - INTERNAL STATE
         **************************************************/
        private List<SObject> readRecords = new List<SObject>();
        private Map<Schema.SObjectType, List<Schema.ChildRelationship>> childrenRelMap = new Map<Schema.SObjectType, List<Schema.ChildRelationship>>();
        private Map<String, ChildRecords> childMap = new Map<String, ChildRecords>();
        private Boolean testLimits = false;

        /**************************************************
         * READER API - HELPER METHODS (CHAINABLE)
         **************************************************/

        /**
         * Add the root record for the next read() invocation
         * @param {SObject} record - the root record type to add
         * @returns {Base} for chaining
         **/
        public MockReader addReadRecord(SObject record) {
            // set a faux id
            setFauxId(record);
            // conditionally add child meta
            Schema.SObjectType recordSobjectType = record.getSObjectType();
            if (!this.childrenRelMap.containsKey(recordSobjectType)) {
                this.childrenRelMap.put(
                    recordSobjectType,
                    recordSobjectType.getDescribe().getChildRelationships()
                );
            }
            // add the root
            this.readRecords.add(record);

            return this;
        }

        /**
         * Appends the current record to the read list the given number of times INCLUDING the current record.
         * @param {Integer} number of times to repeat the current record
         * @return {Base} this instance for chaining
         */
        public MockReader repeat(Integer repeatCount) {
            return repeat(repeatCount, null, null);
        }

        /**
         * Appends the current record to the read list the given number of times INCLUDING the current record,
         * replacing the strings provided.
         * @param {Integer} repeatCount - number of times to repeat the current record
         * @param {Map<Schema.SObjectField, Object>} fieldMap - a map of fields to the values that will be written to them
         * @param {String} replacement - for String values in fieldMap, a string sequence to be replaced with the position of
         * the current item in the read list (i.e. Integer.toString())
         * @return {Base} this instance for chaining
         */
        public MockReader repeat(
            Integer repeatCount,
            Map<Schema.SObjectField, Object> fieldMap,
            String replacement
        ) {
            SObject curr = readRecords.get(readRecords.size() - 1);
            for (Integer pos = 0; pos < repeatCount; pos++) {
                // first iteration the target is curr itself so that repeat count is inclusive of the original
                SObject target = pos == 0 ? curr : curr.clone(false, true);
                if (fieldMap != null && fieldMap.size() > 0) {
                    for (Schema.SObjectField field : fieldMap.keySet()) {
                        replaceAndWrite(
                            target,
                            field,
                            fieldMap.get(field),
                            pos,
                            replacement
                        );
                    }
                }
                if (pos > 0) {
                    addReadRecord(target);
                }
            }

            return this;
        }

        private void replaceAndWrite(
            SObject record,
            Schema.SObjectField field,
            Object value,
            Integer position,
            String positionReplacement
        ) {
            if (String.isNotBlank(positionReplacement)) {
                try {
                    value = ((String) value)
                        .replaceAll(positionReplacement, position.toString());
                } catch (Exception e) {
                    // not a String
                }
            }
            record.put(field, value);
        }

        public MockReader relateChild(SObject child) {
            return relateChild(child, this.readRecords.size() - 1);
        }

        public MockReader relateChild(
            SObject child,
            Integer rootRecordPosition
        ) {
            // set faux id
            setFauxId(child);
            // find the relationship name
            SObject parent = this.readRecords.get(rootRecordPosition);
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
                throw new TestProxyException(
                    childType.getDescribe().getName() +
                        ' is not a valid child of ' +
                        parentType.getDescribe().getName()
                );
            }

            // get or init ChildRecords by faux id of the parent
            String fauxParentId = this.readRecords.get(rootRecordPosition).Id;
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

        public MockReader relateParent(
            SObject parent,
            Schema.SObjectField field
        ) {
            return relateParent(parent, field, this.readRecords.size() - 1);
        }

        public MockReader relateParent(
            SObject parent,
            Schema.SObjectField field,
            Integer rootRecordPosition
        ) {
            // set faux id
            setFauxId(parent);
            // normalize relationship name
            String rawName = field.getDescribe().getName();
            String relName = rawName.endsWith('__c')
                ? rawName.replace('__c', '__r')
                : rawName.replace('Id', '');
            // set both foreign key and related object attributes
            setRootFieldDynamic(rootRecordPosition, rawName, parent.Id);
            setRootFieldDynamic(rootRecordPosition, relName, parent);

            return this;
        }

        private void setRootFieldDynamic(
            Integer rootRecordPosition,
            String fieldKey,
            Object fieldValue
        ) {
            // serialize and deserialize
            SObject root = this.readRecords.get(rootRecordPosition);
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
            this.readRecords[rootRecordPosition] = newRoot;
        }

        /**
         * When invoked, a minimal overhead query will be executed for each call to read() such
         * that limits testing can be simulated. Note that otal queries can be simulated but rows
         * retrieved cannot.
         */
        public MockReader testLimits() {
            this.testLimits = true;

            return this;
        }

        public List<SObject> read() {
            // read with the default options
            return read(new ReadOptions());
        }

        public ReadOptions readOptions() {
            return new ReadOptions();
        }

        /**
         * @description Read the previously constructed SObject list
         * @param {ReadOptions} options
         * @returns {List<SObject>}
         */
        public List<SObject> read(ReadOptions readOptions) {
            // conditionally mock limits
            if (this.testLimits == true) {
                Integer cnt = [SELECT COUNT() FROM Account LIMIT 1];
            }
            // create the list for return
            List<SObject> result = readOptions.resetState
                ? this.readRecords.deepClone(true, true, true)
                : this.readRecords;
            // conditionally recalculate formulas on result
            if (readOptions.recaclFormulas) {
                System.Formula.recalculateFormulas(result);
            }
            // conditionaly reset internal state for subsequent mock
            if (readOptions.resetState) {
                this.readRecords.clear();
                this.childMap.clear();
                this.testLimits = false;
            }

            return result;
        }
    }

    public class ReadOptions {
        public Boolean resetState = true;
        public Boolean recaclFormulas = false;
        private ReadOptions() {
        }
        public ReadOptions resetState(Boolean flag) {
            this.resetState = flag;

            return this;
        }
        public ReadOptions recaclFormulas(Boolean flag) {
            this.recaclFormulas = flag;

            return this;
        }
    }

    public class ChildRecords {
        public Integer totalSize = 0;
        public Boolean done = true;
        public List<SObject> records = new List<SObject>();
        /** @constructor */
        private ChildRecords() {
        }

        public void add(SObject child) {
            this.records.add(child);
            this.totalSize = this.records.size();
        }
    }

    private class TestProxyException extends Exception {
    }

    /******************************************************************
     * BOOTSTRAP TESTS
     *   - covers Proxy as well as functionality in TestProxy
     ******************************************************************/

    private static final String ACCT_NAME = 'Root Account ';
    private static final String PARENT_NAME = 'Parent Account';
    private static final String CT_FNAME = 'Child';
    private static final String CT_LNAME = 'Contact ';

    private static String reflected;
    private static String readerClassName;

    private class TestMockTarget implements Proxy.DbReader {
        public String readStateArg;

        public List<Account> getAccountsAndChildren() {
            return (List<Account>) Proxy.db.read(this);
        }

        public List<SObject> read(Object ctx) {
            this.readStateArg = (String) Proxy.reflect(ctx);
            return [
                SELECT
                    Id,
                    Parent.Name,
                    (SELECT FirstName, LastName FROM Contacts)
                FROM Account
            ];
        }
    }

    private class TestMock extends TestProxy.Base {
        public override Object trap(Object value, String key) {
            String changeReflection = UUID.randomUUID().toString();
            reflected = changeReflection;

            return changeReflection;
        }

        public override List<SObject> read(Proxy.DbReader reader, Object ctx) {
            // capture classname for assertion
            readerClassName = getClassName(reader);

            MockReader mockRead = new MockReader();
            // return 5 Accounts that each have a parent and 5 child Contacts
            mockRead.addReadRecord(new Account());
            mockRead.relateParent(
                new Account(Name = PARENT_NAME),
                Schema.Account.ParentId
            );
            for (Integer i = 0, k = 5; i < k; i++) {
                mockRead.relateChild(
                    new Contact(
                        FirstName = CT_FNAME,
                        LastName = CT_LNAME + i.toString()
                    )
                );
            }
            String positionReplacement = '<replace>';
            mockRead.repeat(
                5,
                new Map<Schema.SObjectField, Object>{
                    Schema.Account.Name => ACCT_NAME +
                    positionReplacement // set name here to test replacement
                },
                positionReplacement
            );

            return mockRead.read();
        }
    }

    @isTest
    /**
     * @description Validates that the reflection API:
     *   (1) returns the passed-in value when not mocked
     *   (2) returns the mocked value when mocked
     */
    private static void validateReflectionIntercept() {
        // validate normal reflection
        TestMockTarget target = new TestMockTarget();
        String original = 'someContext';
        target.read(original);
        Assert.areEqual(original, target.readStateArg);
        // validate mocking works as expected
        Proxy.singleton = new TestMock();
        target.read(original);
        Assert.areEqual(reflected, target.readStateArg);
    }

    @isTest
    /**
     * @description Validates that the reader api:
     *   (1) invokes the passed-in reader when not mocked, returning the expected result
     *   (2) utilizes the mock singleton and returns the mocked response
     */
    private static void validateDbReaderIntercept() {
        // assert no results in actual test db
        TestMockTarget target = new TestMockTarget();
        Assert.areEqual(0, target.getAccountsAndChildren().size());
        // mock and assert the results
        Proxy.singleton = new TestMock();
        List<Account> mockResults = target.getAccountsAndChildren();
        // assert expected shape
        Assert.areEqual(5, mockResults.size());
        for (Integer i = 0, k = mockResults.size(); i < k; i++) {
            Account a = mockResults[i];
            Assert.areEqual(ACCT_NAME + i.toString(), a.Name);
            Assert.areEqual(PARENT_NAME, a.Parent.Name);
            for (Integer c = 0, j = a.Contacts.size(); c < j; c++) {
                Contact ct = a.Contacts.get(c);
                Assert.areEqual(CT_FNAME, ct.FirstName);
                Assert.areEqual(CT_LNAME + c.toString(), ct.LastName);
            }
        }
    }

    @isTest
    /**
     * @description Validates that Proxy.DbReader classname introspection returns as expected.
     */
    private static void validateIntrospectClassname() {
        // set singleton mock and invoke target
        Proxy.singleton = new TestMock();
        new TestMockTarget().getAccountsAndChildren();
        Assert.areEqual('TestMockTarget', readerClassName); // inner class name, but won't print
    }

    @isTest
    /**
     * @description Validates that a configured default proxy is used when configured
     */
    private static void validateDefaultProxyRespected() {
        String orgDefault;
        try {
            orgDefault = System.Label.get(null, 'DefaultProxy');
        } catch (Exception e) {
            orgDefault = '';
        }
        Assert.areEqual(orgDefault, Proxy.DEF_PROXY);
    }

    @isTest
    private static void validateDefaultProxyIsSingleton() {
        // override DEF_PROXY and assert singleton is properly assigned
        Proxy.DEF_PROXY = 'TestProxy.Base';
        Assert.isTrue(Proxy.singleton instanceof TestProxy.Base);
        // reset and test again
        Proxy.singleton = null;
        Proxy.DEF_PROXY = '';
        Assert.isNotNull(Proxy.singleton);
    }

    @isTest
    private static void coverProxyDbOperations() {
        List<Account> accts = new List<Account>();
        Assert.areEqual(0, Proxy.db.insertRecords(accts).size());
        Assert.areEqual(0, Proxy.db.updateRecords(accts).size());
        Assert.areEqual(0, Proxy.db.upsertRecords(accts).size());
        Assert.areEqual(0, Proxy.db.deleteRecords(accts).size());
        Assert.areEqual(0, Proxy.db.undeleteRecords(accts).size());
    }
}
