/**
 * @description Provides APIs for trapping database reads and writes and assignment operands.
 * Provided under the MIT License github.com/kev4ev/apex-proxy
 */

public virtual inherited sharing class Proxy {
    /**
     * @description singleton instance that can only be set (externally) during test execution
     */
    public static Proxy singleton {
        get {
            if (singleton == null) {
                singleton = String.isBlank(DEF_PROXY)
                    ? new Proxy()
                    : (Proxy) Type.forName(DEF_PROXY).newInstance();
            }

            return singleton;
        }
        set {
            if (Test.isRunningTest()) {
                singleton = value;
            }
        }
    }

    @testVisible
    /**
     * @description Returns the configured default proxy, if existing, or null. Test-overridable.
     */
    private static String DEF_PROXY {
        get {
            if (DEF_PROXY == null) {
                try {
                    // null ns defaults to package ns or 'c' when unpackaged
                    DEF_PROXY = System.Label.get(null, 'DefaultProxy') ?? '';
                } catch (Exception e) {
                    // exception *will* be thrown if label does not exist in the ns
                    DEF_PROXY = '';
                }
            }

            return DEF_PROXY;
        }
        set {
            if (Test.isRunningTest()) {
                DEF_PROXY = value;
            }
        }
    }

    /**********************
     * TOP-LEVEL APIs:
     *   1. reflect
     *   2. db
     *   3. mock (only available during unit test execution)
     ***********************/

    /**********************
     * REFLECT API
     ***********************/

    /** @description a simple API for trapping and reflecting values in setters */
    public static Object reflect(Object value) {
        return reflect(value, null);
    }

    /**
     * @description a simple API for trapping and reflecting values in setters, including
     * a key to indicate what value is being trapped.
     */
    public static Object reflect(Object value, String key) {
        return singleton.trap(value, key);
    }

    /**********************
     * DB API
     ***********************/

    public static final Db db = new Db();

    public interface DbReader {
        List<SObject> read(Object readContext);
    }

    public class Db {
        private Db() {
        }

        /**********************
         * READ API
         ***********************/

        public List<SObject> read(DbReader reader) {
            return this.read(reader, null);
        }

        public List<SObject> read(DbReader reader, Object readContext) {
            return singleton.read(reader, readContext);
        }

        /**********************
         * WRITE API
         ***********************/

        public List<Database.SaveResult> insertRecords(List<SObject> records) {
            return singleton.insertRecords(records);
        }
        public List<Database.SaveResult> updateRecords(List<SObject> records) {
            return singleton.updateRecords(records);
        }
        public List<Database.UpsertResult> upsertRecords(
            List<SObject> records
        ) {
            return singleton.upsertRecords(records);
        }
        public List<Database.DeleteResult> deleteRecords(
            List<SObject> records
        ) {
            return singleton.deleteRecords(records);
        }
        public List<Database.UndeleteResult> undeleteRecords(
            List<SObject> records
        ) {
            return singleton.undeleteRecords(records);
        }
    }

    /*********************************
     * OVERRIDEABLE METHODS
     *********************************/

    /**
     * @description reflect API implementation - allows you to trap a value
     * at any point in code execution and introspect its value, along with an
     * optional key indicating what value is being passed.
     */
    public virtual Object trap(Object value, String key) {
        return value;
    }

    /** @description db.read() implementation */
    public virtual List<SObject> read(DbReader reader, Object readContext) {
        return reader.read(readContext);
    }

    /** @description db.insertRecords() implementation */
    public virtual List<Database.SaveResult> insertRecords(
        List<SObject> records
    ) {
        return System.Database.insert(records);
    }

    /** @description db.updateRecords() implementation */
    public virtual List<Database.SaveResult> updateRecords(
        List<SObject> records
    ) {
        return System.Database.update(records);
    }

    /** @description db.upsertRecords() implementation */
    public virtual List<Database.UpsertResult> upsertRecords(
        List<SObject> records
    ) {
        return System.Database.upsert(records);
    }

    /** @description db.deleteRecords() implementation */
    public virtual List<Database.DeleteResult> deleteRecords(
        List<SObject> records
    ) {
        return System.Database.delete(records);
    }

    /** @description db.undeleteRecords() implementation */
    public virtual List<Database.UndeleteResult> undeleteRecords(
        List<SObject> records
    ) {
        return System.Database.undelete(records);
    }

    /**********************
     * HELPER METHODS
     ***********************/

    /** @description common api for classname introspection - ONLY returns inner class name if not a top-level class */
    public static String introspectName(Object instance) {
        return singleton.getClassName(instance);
    }

    /** @description provided for backward compat */
    protected String getClassName(Object instance) {
        return String.valueOf(instance).split(':')[0];
    }

    /**********************
     * MOCK API
     ***********************/

    @testVisible
    private static Mock mockSingleton {
        get {
            if (mockSingleton == null) {
                mockSingleton = new Mock();
            }

            return mockSingleton;
        }
        set;
    }

    /** @description Acts as a pseudo-ns */
    public static Mock mock {
        get {
            return mockSingleton;
        }
    }

    public static Mock mock() {
        return mock(mockSingleton);
    }

    public static Mock mock(Mock customMock) {
        mockSingleton = customMock;
        singleton = customMock;

        return customMock;
    }

    public virtual class Mock extends Proxy {
        private Map<Schema.SObjectType, Integer> recordIdCounter = new Map<Schema.SObjectType, Integer>();
        private Map<String, MockReader> readMocks = new Map<String, MockReader>();
        private Map<String, Object> trapMocks = new Map<String, Object>();

        /** @description stores the state of each key/value passed to reflect(); useful for introspection / assertions */
        public Map<String, Object> trapAudit { get; private set; }
        /** @description stores the state of each result returned from read(); useful for introspection / assertions */
        public Map<String, List<List<SObject>>> readAudit { get; private set; }

        public Mock() {
            if (!Test.isRunningTest()) {
                throw new MockProxyException(
                    'Mock api is only available during Apex test execution.'
                );
            }
        }

        /************************************************************
         * "STATIC" MOCK HELPER APIs (accessible via Proxy.mock getter)
         ************************************************************/

        /**
         * @description set a a fake Id on an SObject and return it
         */
        public SObject setFauxId(SObject record) {
            record.Id = getFauxId(record);

            return record;
        }

        /**
         * @description get a fake Id for an SObject but do not update the SObject itself
         */
        public String getFauxId(SObject record) {
            return getFauxId(record.getSObjectType());
        }

        /**
         * @description get a fake Id for an SObjectType
         */
        public String getFauxId(Schema.SObjectType sot) {
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
                    posStr.length() < 12
                        ? '0'.repeat(12 - posStr.length())
                        : '',
                    posStr
                }
            );

            return fauxId;
        }

        /******************************************************************
         * MOCK REFLECT API: allows extending class to override
         ******************************************************************/

        public virtual override Object trap(Object value, String key) {
            trapAudit(value, key);
            // return either of the mocked key's value or the actual value
            return trapMocks.get(key) ?? value;
        }

        /** @description Available for use by overriding classes */
        protected void trapAudit(Object value, String key) {
            // capture trapped object for introspection
            if (this.trapAudit == null) {
                this.trapAudit = new Map<String, Object>();
            }
            // store either the key or the last non-keyed object
            this.trapAudit.put(key ?? '', value);
        }

        public void trapMock(String key, Object value) {
            trapMocks.put(key, value);
        }

        /******************************************************************
         * MOCK READ API: allows extending class to override
         ******************************************************************/

        public virtual override List<SObject> read(
            DbReader reader,
            Object readContext
        ) {
            String readerName = getClassName(reader).toLowerCase();
            // return either the previously-suplied mock reader or the passed one
            MockReader mocker = readMocks.get(readerName);
            List<SObject> readRecords = mocker?.read(readContext) ??
                reader.read(readContext);
            readAudit(readerName, readRecords);

            return readRecords;
        }

        protected void readAudit(String readerName, List<SObject> readRecords) {
            if (this.readAudit == null) {
                this.readAudit = new Map<String, List<List<SObject>>>();
            }
            if (this.readAudit.get(readerName) == null) {
                this.readAudit.put(readerName, new List<List<SObject>>());
            }
            this.readAudit.get(readerName).add(readRecords);
        }

        /** @description Use when you want mocking a class in the same namespace only */
        public MockReader mockReader(System.Type readerClass) {
            String qualifiedName = readerClass.getName().toLowerCase();

            return mockReader(
                qualifiedName.contains('.')
                    ? qualifiedName.split('\\.')[1]
                    : qualifiedName
            );
        }

        /** @description Use when you want to include the namespace; it gets stripped from method above */
        public MockReader mockReader(String fullyQualifiedClassName) {
            MockReader mock = new MockReader();
            readMocks.put(fullyQualifiedClassName.toLowerCase(), mock);

            return mock;
        }

        /******************************************************************
         * MOCK WRITE API: allows extending class to override
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
    public virtual class MockReader implements Proxy.DbReader {
        /**************************************************
         * INITIAL STATE
         **************************************************/
        public List<List<SObject>> readAudit { get; private set; }
        private Object readContext;
        private MockReadOptions readOptions {
            get {
                if (readOptions == null) {
                    readOptions = new MockReadOptions(this);
                }

                return readOptions;
            }
            set;
        }

        /**************************************************
         * INTERNAL STATE FROM RESULT-BUILDER API
         **************************************************/
        private List<SObject> readRecords = new List<SObject>();
        private Map<Schema.SObjectType, List<Schema.ChildRelationship>> childrenRelMap = new Map<Schema.SObjectType, List<Schema.ChildRelationship>>();
        private Map<String, MockChildRecords> childMap = new Map<String, MockChildRecords>();
        /** link-relevant state */
        private Integer reads = 0;
        private Integer linkAfterReads;
        private MockReader linked;

        /**************************************************
         * SET OPTIONS
         **************************************************/
        public MockReadOptions setOptions() {
            return this.readOptions;
        }

        /**************************************************
         * READER API - OVERRIDABLE IMPLEMENTATION
         **************************************************/

        public virtual List<SObject> read(Object readContext) {
            this.readContext = readContext;
            // readContext is discarded in default implementation - override to utilize it
            return read();
        }

        /**
         * @description Read the previously constructed SObject list
         * @param {MockReadOptions} [options]
         * @returns {List<SObject>}
         */
        private List<SObject> read() {
            // handle linking
            if (this.linked != null && this.linkAfterReads == this.reads) {
                return this.linked.read(this.readContext);
            }
            // conditionally mock limits
            if (this.readOptions.testLimits == true) {
                Integer cnt = [SELECT COUNT() FROM Account LIMIT 1];
            }

            // create the list for return and persist to readAudit
            List<SObject> result = this.readOptions.cloneRead
                ? this.readRecords.deepClone(true, true, true)
                : this.readRecords;
            if (this.readAudit == null) {
                this.readAudit = new List<List<SObject>>();
            }
            this.readAudit.add(result);

            // conditionally recalculate formulas on result
            if (this.readOptions.recaclFormulas) {
                System.Formula.recalculateFormulas(result);
            }

            // conditionaly reset internal state for subsequent mock
            if (this.readOptions.clearStateOnRead) {
                this.readRecords.clear();
                this.childMap.clear();
            }
            // handle linking state
            this.reads += 1;

            return result;
        }

        /**************************************************
         * LINK API
         **************************************************/
        public void link(MockReader linkedReader) {
            link(linkedReader, 1);
        }

        public void link(MockReader linkedReader, Integer linkAfterReads) {
            this.linked = linkedReader;
            this.linkAfterReads = linkAfterReads;
        }

        /**************************************************
         * RESULT-BUILDER API
         **************************************************/

        public MockReader addReadRecords(List<SObject> records) {
            for (SObject record : records) {
                addReadRecord(record);
            }

            return this;
        }

        /**
         * Add the root record for the next read() invocation
         * @param {SObject} record - the root record type to add
         * @returns {Base} for chaining
         **/
        public MockReader addReadRecord(SObject record) {
            // set a faux id
            Proxy.mock.setFauxId(record);
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
            Proxy.mock.setFauxId(child);
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
                throw new MockProxyException(
                    childType.getDescribe().getName() +
                        ' is not a valid child of ' +
                        parentType.getDescribe().getName()
                );
            }

            // get or init MockChildRecords by faux id of the parent
            String fauxParentId = this.readRecords.get(rootRecordPosition).Id;
            MockChildRecords children = this.childMap.get(fauxParentId);
            if (children == null) {
                children = new MockChildRecords();
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
            Proxy.mock.setFauxId(parent);
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
    }

    /**
     * @description Options for read operations during mocking
     */
    public class MockReadOptions {
        private final MockReader reader;
        /**
         * Read mode:
         *   - in default (non-clone) mode the records returned are always the in-memory
         * pointers to the original read records; useful to observe changes made
         * in target code from unit tests without using readAdut
         *   - in clone mode the read records are deep-cloned before return; use with caution
         * as in most cases this is not necessary; link API can be used to similar effect
         */
        public Boolean cloneRead = false;
        public Boolean clearStateOnRead = false;
        public Boolean recaclFormulas = false;
        /**
         * @description when true, a minimal overhead query will be executed for each call to read() such
         * that limits testing can be simulated. Note that otal queries can be simulated but rows
         * retrieved cannot.
         */
        public Boolean testLimits = false;

        private MockReadOptions(MockReader reader) {
            this.reader = reader;
        }

        public MockReader endSetOptions() {
            return this.reader;
        }

        public MockReadOptions cloneRead(Boolean flag) {
            this.cloneRead = flag;

            return this;
        }

        public MockReadOptions clearStateOnRead(Boolean flag) {
            this.clearStateOnRead = flag;

            return this;
        }

        public MockReadOptions recaclFormulas(Boolean flag) {
            this.recaclFormulas = flag;

            return this;
        }

        public MockReadOptions testLimits(Boolean flag) {
            this.testLimits = flag;

            return this;
        }
    }

    public class MockChildRecords {
        public Integer totalSize = 0;
        public Boolean done = true;
        public List<SObject> records = new List<SObject>();
        /** @constructor */
        private MockChildRecords() {
        }

        public void add(SObject child) {
            this.records.add(child);
            this.totalSize = this.records.size();
        }
    }

    private class MockProxyException extends Exception {
    }
}
