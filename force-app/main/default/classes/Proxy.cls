/**
 * @version 2.0.0
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

    /****************************************************************************************
     * TOP-LEVEL APIs:
     *   1. reflect
     *   2. db (pseudo namespace for db read/write operations)
     *   3. mock (only available during unit test execution)
     ****************************************************************************************/

    /****************************************************************************************
     * REFLECT API
     * A simple API for trapping and reflecting values in setters and expressions.
     ****************************************************************************************/

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

    /****************************************************************************************
     * DB "Namespace"
     * Read and Write APIs for database operations.
     * All methods delegate to the singleton instance
     ****************************************************************************************/

    public static final Db db = new Db();

    public interface DbReader {
        List<SObject> read(Object readContext);
    }

    public class Db extends DbWrite {
        private Db() {
        }

        /***************
         * DB READ API
         ***************/

        /** INLINE STYLE: best for greenfield and/or quick implementations */

        public List<SObject> read(List<SObject> records, System.Type caller) {
            return this.read(records, caller, null);
        }

        public List<SObject> read(
            List<SObject> records,
            System.Type caller,
            Object readContext
        ) {
            return singleton.read(records, caller, readContext);
        }

        /** IMPLEMENTATION STYLE: best for use with existing frameworks or patterns like FFLIB / Selector pattern */

        public List<SObject> read(DbReader reader) {
            return this.read(reader, null);
        }

        public List<SObject> read(DbReader reader, Object readContext) {
            return singleton.read(reader, readContext);
        }

        /***************
         * DB WRITE API
         ***************/
        // all dml methods implemented in DbWrite class at far bottom for conciseness
    }

    /****************************************************************************************
     * MOCK API:
     * Only available during test execution
     * Allows for powerful mocking of db reads and writes as well as the reflect api
     * Invoke in a unit test via: Proxy.mock() or Proxy.mock(customMockInstance)
     ****************************************************************************************/

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

        /**
         * @description "static" helper to relate dynamically relate child to parent
         */
        public SObject relateParent(
            SObject child,
            SObject parent,
            Schema.SObjectField relationField
        ) {
            // create throwaway MockReader
            MockReader reader = new MockReader();
            reader.addReadRecord(child).relateParent(parent, relationField);

            return reader.readRecords[0];
        }

        /**
         * @description "static" helper to relate dynamically relate parent to child
         */
        public SObject relateParent(SObject parent, SObject child) {
            // create throwaway MockReader
            MockReader reader = new MockReader();
            reader.addReadRecord(parent).relateChild(child);

            return reader.readRecords[0];
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

        /** @description use to introspect a value passed to the reflect api with this key */
        public void trapMock(String key) {
            trapMock(key, null);
        }

        /** @description use to **replace the return value** of a value passed to the reflect api with this key */
        public void trapMock(String key, Object value) {
            trapMocks.put(key, value);
        }

        /******************************************************************
         * MOCK READ API: allows extending class to override
         ******************************************************************/

        /** @description db.read() mock INLINE-STYLE */
        public override List<SObject> read(
            List<SObject> records,
            System.Type caller,
            Object readContext
        ) {
            String callerName = normalizeClassName(caller);
            // return either the previously-suplied mock reader or the passed one
            MockReader mocker = readMocks.get(callerName);
            List<SObject> readRecords = mocker?.read(readContext) ?? records;
            readAudit(callerName, readRecords);

            return readRecords;
        }

        /** @description db.read() mock IMPLEMENTATION-STYLE */
        public virtual override List<SObject> read(
            DbReader reader,
            Object readContext
        ) {
            String readerName = normalizeClassName(reader);
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

        /** @description Generate a MockReader instance for the Type to mock */
        public MockReader mockReader(System.Type readerType) {
            MockReader mocker = new MockReader();
            String fullyQualifiedName = readerType.getName();
            String normalizedName = normalizeClassName(readerType);
            readMocks.put(normalizedName, mocker);

            return mocker;
        }

        /******************************************************************
         * MOCK WRITE API: allows extending class to override
         ******************************************************************/

        // insert - single record; delegates to list master; override for custom result
        public virtual override Database.SaveResult insertRecords(
            SObject record
        ) {
            return insertRecords(record, false);
        }
        public virtual override Database.SaveResult insertRecords(
            SObject record,
            Boolean allOrNone
        ) {
            return insertRecords(new List<SObject>{ record }, allOrNone)[0];
        }
        public virtual override Database.SaveResult insertRecords(
            SObject record,
            Database.DMLOptions dmlOptions
        ) {
            return insertRecords(new List<SObject>{ record }, dmlOptions)[0];
        }
        public virtual override Database.SaveResult insertRecords(
            SObject record,
            Boolean allOrNone,
            System.AccessLevel accessLevel
        ) {
            return insertRecords(
                new List<SObject>{ record },
                allOrNone,
                accessLevel
            )[0];
        }
        public virtual override Database.SaveResult insertRecords(
            SObject record,
            Database.DMLOptions dmlOptions,
            System.AccessLevel accessLevel
        ) {
            return insertRecords(
                new List<SObject>{ record },
                dmlOptions,
                accessLevel
            )[0];
        }
        // insert - list; master returns size-matched list of null results
        public virtual override List<Database.SaveResult> insertRecords(
            List<SObject> records
        ) {
            return insertRecords(records, false);
        }
        public virtual override List<Database.SaveResult> insertRecords(
            List<SObject> records,
            Boolean allOrNone
        ) {
            return new List<Database.SaveResult>(records.size());
        }
        public virtual override List<Database.SaveResult> insertRecords(
            List<SObject> records,
            Database.DMLOptions dmlOptions
        ) {
            return new List<Database.SaveResult>(records.size());
        }
        public virtual override List<Database.SaveResult> insertRecords(
            List<SObject> records,
            Boolean allOrNone,
            System.AccessLevel accessLevel
        ) {
            return new List<Database.SaveResult>(records.size());
        }
        public virtual override List<Database.SaveResult> insertRecords(
            List<SObject> records,
            Database.DMLOptions dmlOptions,
            System.AccessLevel accessLevel
        ) {
            return new List<Database.SaveResult>(records.size());
        }
        // update - single record
        public virtual override Database.SaveResult updateRecords(
            SObject record
        ) {
            return updateRecords(record, false);
        }
        public virtual override Database.SaveResult updateRecords(
            SObject record,
            Boolean allOrNone
        ) {
            return updateRecords(new List<SObject>{ record }, allOrNone)[0];
        }
        public virtual override Database.SaveResult updateRecords(
            SObject record,
            Database.DMLOptions dmlOptions
        ) {
            return updateRecords(new List<SObject>{ record }, dmlOptions)[0];
        }
        public virtual override Database.SaveResult updateRecords(
            SObject record,
            Boolean allOrNone,
            System.AccessLevel accessLevel
        ) {
            return updateRecords(
                new List<SObject>{ record },
                allOrNone,
                accessLevel
            )[0];
        }
        public virtual override Database.SaveResult updateRecords(
            SObject record,
            Database.DMLOptions dmlOptions,
            System.AccessLevel accessLevel
        ) {
            return updateRecords(
                new List<SObject>{ record },
                dmlOptions,
                accessLevel
            )[0];
        }
        // update - list
        public virtual override List<Database.SaveResult> updateRecords(
            List<SObject> records
        ) {
            return updateRecords(records, false);
        }
        public virtual override List<Database.SaveResult> updateRecords(
            List<SObject> records,
            Boolean allOrNone
        ) {
            return new List<Database.SaveResult>(records.size());
        }
        public virtual override List<Database.SaveResult> updateRecords(
            List<SObject> records,
            Database.DMLOptions dmlOptions
        ) {
            return new List<Database.SaveResult>(records.size());
        }
        public virtual override List<Database.SaveResult> updateRecords(
            List<SObject> records,
            Boolean allOrNone,
            System.AccessLevel accessLevel
        ) {
            return new List<Database.SaveResult>(records.size());
        }
        public virtual override List<Database.SaveResult> updateRecords(
            List<SObject> records,
            Database.DMLOptions dmlOptions,
            System.AccessLevel accessLevel
        ) {
            return new List<Database.SaveResult>(records.size());
        }
        // upsert - single record
        public virtual override Database.UpsertResult upsertRecords(
            SObject record
        ) {
            return upsertRecords(record, null, false);
        }
        public virtual override Database.UpsertResult upsertRecords(
            SObject record,
            Boolean allOrNone
        ) {
            return upsertRecords(record, null, allOrNone);
        }
        public virtual override Database.UpsertResult upsertRecords(
            SObject record,
            Schema.SObjectField externalIdField
        ) {
            return upsertRecords(record, externalIdField, false);
        }
        public virtual override Database.UpsertResult upsertRecords(
            SObject record,
            Schema.SObjectField externalIdField,
            Boolean allOrNone
        ) {
            return upsertRecords(
                new List<SObject>{ record },
                externalIdField,
                allOrNone
            )[0];
        }
        public virtual override Database.UpsertResult upsertRecords(
            SObject record,
            Boolean allOrNone,
            System.AccessLevel accessLevel
        ) {
            return upsertRecords(record, null, allOrNone, accessLevel);
        }
        public virtual override Database.UpsertResult upsertRecords(
            SObject record,
            Schema.SObjectField externalIdField,
            Boolean allOrNone,
            System.AccessLevel accessLevel
        ) {
            return upsertRecords(
                new List<SObject>{ record },
                externalIdField,
                allOrNone,
                accessLevel
            )[0];
        }
        // upsert - list
        public virtual override List<Database.UpsertResult> upsertRecords(
            List<SObject> records
        ) {
            return upsertRecords(records, null, false);
        }
        public virtual override List<Database.UpsertResult> upsertRecords(
            List<SObject> records,
            Boolean allOrNone
        ) {
            return upsertRecords(records, null, allOrNone);
        }
        public virtual override List<Database.UpsertResult> upsertRecords(
            List<SObject> records,
            Schema.SObjectField externalIdField
        ) {
            return upsertRecords(records, externalIdField, false);
        }
        public virtual override List<Database.UpsertResult> upsertRecords(
            List<SObject> records,
            Schema.SObjectField externalIdField,
            Boolean allOrNone
        ) {
            return new List<Database.UpsertResult>(records.size());
        }
        public virtual override List<Database.UpsertResult> upsertRecords(
            List<SObject> records,
            Boolean allOrNone,
            System.AccessLevel accessLevel
        ) {
            return upsertRecords(records, null, allOrNone, accessLevel);
        }
        public virtual override List<Database.UpsertResult> upsertRecords(
            List<SObject> records,
            Schema.SObjectField externalIdField,
            Boolean allOrNone,
            System.AccessLevel accessLevel
        ) {
            return new List<Database.UpsertResult>(records.size());
        }
        // delete - single SObject
        public virtual override Database.DeleteResult deleteRecords(
            SObject record
        ) {
            return deleteRecords(record, false);
        }
        public virtual override Database.DeleteResult deleteRecords(
            SObject record,
            Boolean allOrNone
        ) {
            return deleteRecords(new List<SObject>{ record }, allOrNone)[0];
        }
        public virtual override Database.DeleteResult deleteRecords(
            SObject record,
            Boolean allOrNone,
            System.AccessLevel accessLevel
        ) {
            return deleteRecords(
                new List<SObject>{ record },
                allOrNone,
                accessLevel
            )[0];
        }
        // delete - single Id
        public virtual override Database.DeleteResult deleteRecords(
            Id recordId
        ) {
            return deleteRecords(recordId, false);
        }
        public virtual override Database.DeleteResult deleteRecords(
            Id recordId,
            Boolean allOrNone
        ) {
            return deleteRecords(new List<Id>{ recordId }, allOrNone)[0];
        }
        public virtual override Database.DeleteResult deleteRecords(
            Id recordId,
            Boolean allOrNone,
            System.AccessLevel accessLevel
        ) {
            return deleteRecords(
                new List<Id>{ recordId },
                allOrNone,
                accessLevel
            )[0];
        }
        // delete - list SObject
        public virtual override List<Database.DeleteResult> deleteRecords(
            List<SObject> records
        ) {
            return deleteRecords(records, false);
        }
        public virtual override List<Database.DeleteResult> deleteRecords(
            List<SObject> records,
            Boolean allOrNone
        ) {
            return new List<Database.DeleteResult>(records.size());
        }
        public virtual override List<Database.DeleteResult> deleteRecords(
            List<SObject> records,
            Boolean allOrNone,
            System.AccessLevel accessLevel
        ) {
            return new List<Database.DeleteResult>(records.size());
        }
        // delete - list Id
        public virtual override List<Database.DeleteResult> deleteRecords(
            List<Id> recordIds
        ) {
            return deleteRecords(recordIds, false);
        }
        public virtual override List<Database.DeleteResult> deleteRecords(
            List<Id> recordIds,
            Boolean allOrNone
        ) {
            return new List<Database.DeleteResult>(recordIds.size());
        }
        public virtual override List<Database.DeleteResult> deleteRecords(
            List<Id> recordIds,
            Boolean allOrNone,
            System.AccessLevel accessLevel
        ) {
            return new List<Database.DeleteResult>(recordIds.size());
        }
        // undelete - single SObject
        public virtual override Database.UndeleteResult undeleteRecords(
            SObject record
        ) {
            return undeleteRecords(record, false);
        }
        public virtual override Database.UndeleteResult undeleteRecords(
            SObject record,
            Boolean allOrNone
        ) {
            return undeleteRecords(new List<SObject>{ record }, allOrNone)[0];
        }
        public virtual override Database.UndeleteResult undeleteRecords(
            SObject record,
            Boolean allOrNone,
            System.AccessLevel accessLevel
        ) {
            return undeleteRecords(
                new List<SObject>{ record },
                allOrNone,
                accessLevel
            )[0];
        }
        // undelete - single Id
        public virtual override Database.UndeleteResult undeleteRecords(
            Id recordId
        ) {
            return undeleteRecords(recordId, false);
        }
        public virtual override Database.UndeleteResult undeleteRecords(
            Id recordId,
            Boolean allOrNone
        ) {
            return undeleteRecords(new List<Id>{ recordId }, allOrNone)[0];
        }
        public virtual override Database.UndeleteResult undeleteRecords(
            Id recordId,
            Boolean allOrNone,
            System.AccessLevel accessLevel
        ) {
            return undeleteRecords(
                new List<Id>{ recordId },
                allOrNone,
                accessLevel
            )[0];
        }
        // undelete - list SObject
        public virtual override List<Database.UndeleteResult> undeleteRecords(
            List<SObject> records
        ) {
            return undeleteRecords(records, false);
        }
        public virtual override List<Database.UndeleteResult> undeleteRecords(
            List<SObject> records,
            Boolean allOrNone
        ) {
            return new List<Database.UndeleteResult>(records.size());
        }
        public virtual override List<Database.UndeleteResult> undeleteRecords(
            List<SObject> records,
            Boolean allOrNone,
            System.AccessLevel accessLevel
        ) {
            return new List<Database.UndeleteResult>(records.size());
        }
        // undelete - list Id
        public virtual override List<Database.UndeleteResult> undeleteRecords(
            List<Id> recordIds
        ) {
            return undeleteRecords(recordIds, false);
        }
        public virtual override List<Database.UndeleteResult> undeleteRecords(
            List<Id> recordIds,
            Boolean allOrNone
        ) {
            return new List<Database.UndeleteResult>(recordIds.size());
        }
        public virtual override List<Database.UndeleteResult> undeleteRecords(
            List<Id> recordIds,
            Boolean allOrNone,
            System.AccessLevel accessLevel
        ) {
            return new List<Database.UndeleteResult>(recordIds.size());
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

        /**
         * @description !!Important!! readContext is discarded in default implementation.
         * override if you need to utilize it
         */
        public virtual List<SObject> read(Object readContext) {
            this.readContext = readContext;
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
            if (String.isBlank(record.Id)) {
                Proxy.mock.setFauxId(record);
            }
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
            if (String.isBlank(child.Id)) {
                Proxy.mock.setFauxId(child);
            }
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
            if (String.isBlank(parent.Id)) {
                Proxy.mock.setFauxId(parent);
            }
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

    private virtual class DbWrite {
        /****************************************************************************************
         * WRITE API
         ****************************************************************************************/

        // insert - single record
        public Database.SaveResult insertRecords(SObject record) {
            return singleton.insertRecords(record);
        }
        public Database.SaveResult insertRecords(
            SObject record,
            Boolean allOrNone
        ) {
            return singleton.insertRecords(record, allOrNone);
        }
        public Database.SaveResult insertRecords(
            SObject record,
            Database.DMLOptions dmlOptions
        ) {
            return singleton.insertRecords(record, dmlOptions);
        }
        public Database.SaveResult insertRecords(
            SObject record,
            Boolean allOrNone,
            System.AccessLevel accessLevel
        ) {
            return singleton.insertRecords(record, allOrNone, accessLevel);
        }
        public Database.SaveResult insertRecords(
            SObject record,
            Database.DMLOptions dmlOptions,
            System.AccessLevel accessLevel
        ) {
            return singleton.insertRecords(record, dmlOptions, accessLevel);
        }
        // insert - list
        public List<Database.SaveResult> insertRecords(List<SObject> records) {
            return singleton.insertRecords(records);
        }
        public List<Database.SaveResult> insertRecords(
            List<SObject> records,
            Boolean allOrNone
        ) {
            return singleton.insertRecords(records, allOrNone);
        }
        public List<Database.SaveResult> insertRecords(
            List<SObject> records,
            Database.DMLOptions dmlOptions
        ) {
            return singleton.insertRecords(records, dmlOptions);
        }
        public List<Database.SaveResult> insertRecords(
            List<SObject> records,
            Boolean allOrNone,
            System.AccessLevel accessLevel
        ) {
            return singleton.insertRecords(records, allOrNone, accessLevel);
        }
        public List<Database.SaveResult> insertRecords(
            List<SObject> records,
            Database.DMLOptions dmlOptions,
            System.AccessLevel accessLevel
        ) {
            return singleton.insertRecords(records, dmlOptions, accessLevel);
        }
        // update - single record
        public Database.SaveResult updateRecords(SObject record) {
            return singleton.updateRecords(record);
        }
        public Database.SaveResult updateRecords(
            SObject record,
            Boolean allOrNone
        ) {
            return singleton.updateRecords(record, allOrNone);
        }
        public Database.SaveResult updateRecords(
            SObject record,
            Database.DMLOptions dmlOptions
        ) {
            return singleton.updateRecords(record, dmlOptions);
        }
        public Database.SaveResult updateRecords(
            SObject record,
            Boolean allOrNone,
            System.AccessLevel accessLevel
        ) {
            return singleton.updateRecords(record, allOrNone, accessLevel);
        }
        public Database.SaveResult updateRecords(
            SObject record,
            Database.DMLOptions dmlOptions,
            System.AccessLevel accessLevel
        ) {
            return singleton.updateRecords(record, dmlOptions, accessLevel);
        }
        // update - list
        public List<Database.SaveResult> updateRecords(List<SObject> records) {
            return singleton.updateRecords(records);
        }
        public List<Database.SaveResult> updateRecords(
            List<SObject> records,
            Boolean allOrNone
        ) {
            return singleton.updateRecords(records, allOrNone);
        }
        public List<Database.SaveResult> updateRecords(
            List<SObject> records,
            Database.DMLOptions dmlOptions
        ) {
            return singleton.updateRecords(records, dmlOptions);
        }
        public List<Database.SaveResult> updateRecords(
            List<SObject> records,
            Boolean allOrNone,
            System.AccessLevel accessLevel
        ) {
            return singleton.updateRecords(records, allOrNone, accessLevel);
        }
        public List<Database.SaveResult> updateRecords(
            List<SObject> records,
            Database.DMLOptions dmlOptions,
            System.AccessLevel accessLevel
        ) {
            return singleton.updateRecords(records, dmlOptions, accessLevel);
        }
        // upsert - single record
        public Database.UpsertResult upsertRecords(SObject record) {
            return singleton.upsertRecords(record);
        }
        public Database.UpsertResult upsertRecords(
            SObject record,
            Boolean allOrNone
        ) {
            return singleton.upsertRecords(record, allOrNone);
        }
        public Database.UpsertResult upsertRecords(
            SObject record,
            Schema.SObjectField externalIdField
        ) {
            return singleton.upsertRecords(record, externalIdField);
        }
        public Database.UpsertResult upsertRecords(
            SObject record,
            Schema.SObjectField externalIdField,
            Boolean allOrNone
        ) {
            return singleton.upsertRecords(record, externalIdField, allOrNone);
        }
        public Database.UpsertResult upsertRecords(
            SObject record,
            Boolean allOrNone,
            System.AccessLevel accessLevel
        ) {
            return singleton.upsertRecords(record, allOrNone, accessLevel);
        }
        public Database.UpsertResult upsertRecords(
            SObject record,
            Schema.SObjectField externalIdField,
            Boolean allOrNone,
            System.AccessLevel accessLevel
        ) {
            return singleton.upsertRecords(
                record,
                externalIdField,
                allOrNone,
                accessLevel
            );
        }
        // upsert - list
        public List<Database.UpsertResult> upsertRecords(
            List<SObject> records
        ) {
            return singleton.upsertRecords(records);
        }
        public List<Database.UpsertResult> upsertRecords(
            List<SObject> records,
            Boolean allOrNone
        ) {
            return singleton.upsertRecords(records, allOrNone);
        }
        public List<Database.UpsertResult> upsertRecords(
            List<SObject> records,
            Schema.SObjectField externalIdField
        ) {
            return singleton.upsertRecords(records, externalIdField);
        }
        public List<Database.UpsertResult> upsertRecords(
            List<SObject> records,
            Schema.SObjectField externalIdField,
            Boolean allOrNone
        ) {
            return singleton.upsertRecords(records, externalIdField, allOrNone);
        }
        public List<Database.UpsertResult> upsertRecords(
            List<SObject> records,
            Boolean allOrNone,
            System.AccessLevel accessLevel
        ) {
            return singleton.upsertRecords(records, allOrNone, accessLevel);
        }
        public List<Database.UpsertResult> upsertRecords(
            List<SObject> records,
            Schema.SObjectField externalIdField,
            Boolean allOrNone,
            System.AccessLevel accessLevel
        ) {
            return singleton.upsertRecords(
                records,
                externalIdField,
                allOrNone,
                accessLevel
            );
        }
        // delete - single SObject
        public Database.DeleteResult deleteRecords(SObject record) {
            return singleton.deleteRecords(record);
        }
        public Database.DeleteResult deleteRecords(
            SObject record,
            Boolean allOrNone
        ) {
            return singleton.deleteRecords(record, allOrNone);
        }
        public Database.DeleteResult deleteRecords(
            SObject record,
            Boolean allOrNone,
            System.AccessLevel accessLevel
        ) {
            return singleton.deleteRecords(record, allOrNone, accessLevel);
        }
        // delete - single Id
        public Database.DeleteResult deleteRecords(Id recordId) {
            return singleton.deleteRecords(recordId);
        }
        public Database.DeleteResult deleteRecords(
            Id recordId,
            Boolean allOrNone
        ) {
            return singleton.deleteRecords(recordId, allOrNone);
        }
        public Database.DeleteResult deleteRecords(
            Id recordId,
            Boolean allOrNone,
            System.AccessLevel accessLevel
        ) {
            return singleton.deleteRecords(recordId, allOrNone, accessLevel);
        }
        // delete - list SObject
        public List<Database.DeleteResult> deleteRecords(
            List<SObject> records
        ) {
            return singleton.deleteRecords(records);
        }
        public List<Database.DeleteResult> deleteRecords(
            List<SObject> records,
            Boolean allOrNone
        ) {
            return singleton.deleteRecords(records, allOrNone);
        }
        public List<Database.DeleteResult> deleteRecords(
            List<SObject> records,
            Boolean allOrNone,
            System.AccessLevel accessLevel
        ) {
            return singleton.deleteRecords(records, allOrNone, accessLevel);
        }
        // delete - list Id
        public List<Database.DeleteResult> deleteRecords(List<Id> recordIds) {
            return singleton.deleteRecords(recordIds);
        }
        public List<Database.DeleteResult> deleteRecords(
            List<Id> recordIds,
            Boolean allOrNone
        ) {
            return singleton.deleteRecords(recordIds, allOrNone);
        }
        public List<Database.DeleteResult> deleteRecords(
            List<Id> recordIds,
            Boolean allOrNone,
            System.AccessLevel accessLevel
        ) {
            return singleton.deleteRecords(recordIds, allOrNone, accessLevel);
        }
        // undelete - single SObject
        public Database.UndeleteResult undeleteRecords(SObject record) {
            return singleton.undeleteRecords(record);
        }
        public Database.UndeleteResult undeleteRecords(
            SObject record,
            Boolean allOrNone
        ) {
            return singleton.undeleteRecords(record, allOrNone);
        }
        public Database.UndeleteResult undeleteRecords(
            SObject record,
            Boolean allOrNone,
            System.AccessLevel accessLevel
        ) {
            return singleton.undeleteRecords(record, allOrNone, accessLevel);
        }
        // undelete - single Id
        public Database.UndeleteResult undeleteRecords(Id recordId) {
            return singleton.undeleteRecords(recordId);
        }
        public Database.UndeleteResult undeleteRecords(
            Id recordId,
            Boolean allOrNone
        ) {
            return singleton.undeleteRecords(recordId, allOrNone);
        }
        public Database.UndeleteResult undeleteRecords(
            Id recordId,
            Boolean allOrNone,
            System.AccessLevel accessLevel
        ) {
            return singleton.undeleteRecords(recordId, allOrNone, accessLevel);
        }
        // undelete - list SObject
        public List<Database.UndeleteResult> undeleteRecords(
            List<SObject> records
        ) {
            return singleton.undeleteRecords(records);
        }
        public List<Database.UndeleteResult> undeleteRecords(
            List<SObject> records,
            Boolean allOrNone
        ) {
            return singleton.undeleteRecords(records, allOrNone);
        }
        public List<Database.UndeleteResult> undeleteRecords(
            List<SObject> records,
            Boolean allOrNone,
            System.AccessLevel accessLevel
        ) {
            return singleton.undeleteRecords(records, allOrNone, accessLevel);
        }
        // undelete - list Id
        public List<Database.UndeleteResult> undeleteRecords(
            List<Id> recordIds
        ) {
            return singleton.undeleteRecords(recordIds);
        }
        public List<Database.UndeleteResult> undeleteRecords(
            List<Id> recordIds,
            Boolean allOrNone
        ) {
            return singleton.undeleteRecords(recordIds, allOrNone);
        }
        public List<Database.UndeleteResult> undeleteRecords(
            List<Id> recordIds,
            Boolean allOrNone,
            System.AccessLevel accessLevel
        ) {
            return singleton.undeleteRecords(recordIds, allOrNone, accessLevel);
        }
    }

    /****************************************************************************************
     * HELPER METHODS: for name introspection and normalization. Due to limitations in the
     * Apex runtime and to keep behavior consistent between INLINE and IMPLEMENTATION read
     * styles, class names are always normalized to their INNERMOST class name. Take care if
     * you are mocking several classes in the same test method as this could lead to conflicts.
     ****************************************************************************************/

    /** @description returns innermost class name if not a top-level class; strips namespaces */
    public static String normalizeClassName(Object instance) {
        String raw = String.valueOf(instance);
        List<String> parts = raw.split(':');

        return normalizeClassName(parts[0]);
    }

    /** @description returns innermost class name if not a top-level class; strips namespaces */
    public static String normalizeClassName(System.Type type) {
        return normalizeClassName(type.getName());
    }

    private static String normalizeClassName(String qualifiedName) {
        List<String> parts = qualifiedName.split('\\.');
        String innermost = parts.get(parts.size() - 1);

        return innermost.toLowerCase();
    }

    /****************************************************************************************
     * PROXY SINGLETON METHODS: OVERRIDEABLE
     ****************************************************************************************/

    /**
     * @description reflect API implementation - allows you to trap a value
     * at any point in code execution and introspect its value, along with an
     * optional key indicating what value is being passed.
     */
    public virtual Object trap(Object value, String key) {
        return value;
    }

    /** @description db.read() INLINE-STYLE */
    public virtual List<SObject> read(
        List<SObject> records,
        System.Type caller,
        Object readContext
    ) {
        return records;
    }

    /** @description db.read() IMPLEMENTATION-STYLE */
    public virtual List<SObject> read(DbReader reader, Object readContext) {
        return reader.read(readContext);
    }

    // insert - single record
    public virtual Database.SaveResult insertRecords(SObject record) {
        return insertRecords(record, false);
    }
    public virtual Database.SaveResult insertRecords(
        SObject record,
        Boolean allOrNone
    ) {
        return System.Database.insert(record, allOrNone);
    }
    public virtual Database.SaveResult insertRecords(
        SObject record,
        Database.DMLOptions dmlOptions
    ) {
        return System.Database.insert(record, dmlOptions);
    }
    public virtual Database.SaveResult insertRecords(
        SObject record,
        Boolean allOrNone,
        System.AccessLevel accessLevel
    ) {
        return System.Database.insert(record, allOrNone, accessLevel);
    }
    public virtual Database.SaveResult insertRecords(
        SObject record,
        Database.DMLOptions dmlOptions,
        System.AccessLevel accessLevel
    ) {
        return System.Database.insert(record, dmlOptions, accessLevel);
    }
    // insert - list
    public virtual List<Database.SaveResult> insertRecords(
        List<SObject> records
    ) {
        return insertRecords(records, false);
    }
    public virtual List<Database.SaveResult> insertRecords(
        List<SObject> records,
        Boolean allOrNone
    ) {
        return System.Database.insert(records, allOrNone);
    }
    public virtual List<Database.SaveResult> insertRecords(
        List<SObject> records,
        Database.DMLOptions dmlOptions
    ) {
        return System.Database.insert(records, dmlOptions);
    }
    public virtual List<Database.SaveResult> insertRecords(
        List<SObject> records,
        Boolean allOrNone,
        System.AccessLevel accessLevel
    ) {
        return System.Database.insert(records, allOrNone, accessLevel);
    }
    public virtual List<Database.SaveResult> insertRecords(
        List<SObject> records,
        Database.DMLOptions dmlOptions,
        System.AccessLevel accessLevel
    ) {
        return System.Database.insert(records, dmlOptions, accessLevel);
    }
    // update - single record
    public virtual Database.SaveResult updateRecords(SObject record) {
        return updateRecords(record, false);
    }
    public virtual Database.SaveResult updateRecords(
        SObject record,
        Boolean allOrNone
    ) {
        return System.Database.update(record, allOrNone);
    }
    public virtual Database.SaveResult updateRecords(
        SObject record,
        Database.DMLOptions dmlOptions
    ) {
        return System.Database.update(record, dmlOptions);
    }
    public virtual Database.SaveResult updateRecords(
        SObject record,
        Boolean allOrNone,
        System.AccessLevel accessLevel
    ) {
        return System.Database.update(record, allOrNone, accessLevel);
    }
    public virtual Database.SaveResult updateRecords(
        SObject record,
        Database.DMLOptions dmlOptions,
        System.AccessLevel accessLevel
    ) {
        return System.Database.update(record, dmlOptions, accessLevel);
    }
    // update - list
    public virtual List<Database.SaveResult> updateRecords(
        List<SObject> records
    ) {
        return updateRecords(records, false);
    }
    public virtual List<Database.SaveResult> updateRecords(
        List<SObject> records,
        Boolean allOrNone
    ) {
        return System.Database.update(records, allOrNone);
    }
    public virtual List<Database.SaveResult> updateRecords(
        List<SObject> records,
        Database.DMLOptions dmlOptions
    ) {
        return System.Database.update(records, dmlOptions);
    }
    public virtual List<Database.SaveResult> updateRecords(
        List<SObject> records,
        Boolean allOrNone,
        System.AccessLevel accessLevel
    ) {
        return System.Database.update(records, allOrNone, accessLevel);
    }
    public virtual List<Database.SaveResult> updateRecords(
        List<SObject> records,
        Database.DMLOptions dmlOptions,
        System.AccessLevel accessLevel
    ) {
        return System.Database.update(records, dmlOptions, accessLevel);
    }
    // upsert - single record
    public virtual Database.UpsertResult upsertRecords(SObject record) {
        return upsertRecords(record, null, false);
    }
    public virtual Database.UpsertResult upsertRecords(
        SObject record,
        Boolean allOrNone
    ) {
        return upsertRecords(record, null, allOrNone);
    }
    public virtual Database.UpsertResult upsertRecords(
        SObject record,
        Schema.SObjectField externalIdField
    ) {
        return upsertRecords(record, externalIdField, false);
    }
    public virtual Database.UpsertResult upsertRecords(
        SObject record,
        Schema.SObjectField externalIdField,
        Boolean allOrNone
    ) {
        return externalIdField != null
            ? System.Database.upsert(record, externalIdField, allOrNone)
            : System.Database.upsert(record, allOrNone);
    }
    public virtual Database.UpsertResult upsertRecords(
        SObject record,
        Boolean allOrNone,
        System.AccessLevel accessLevel
    ) {
        return upsertRecords(record, null, allOrNone, accessLevel);
    }
    public virtual Database.UpsertResult upsertRecords(
        SObject record,
        Schema.SObjectField externalIdField,
        Boolean allOrNone,
        System.AccessLevel accessLevel
    ) {
        return externalIdField != null
            ? System.Database.upsert(
                  record,
                  externalIdField,
                  allOrNone,
                  accessLevel
              )
            : System.Database.upsert(record, allOrNone, accessLevel);
    }
    // upsert - list
    public virtual List<Database.UpsertResult> upsertRecords(
        List<SObject> records
    ) {
        return upsertRecords(records, null, false);
    }
    public virtual List<Database.UpsertResult> upsertRecords(
        List<SObject> records,
        Boolean allOrNone
    ) {
        return upsertRecords(records, null, allOrNone);
    }
    public virtual List<Database.UpsertResult> upsertRecords(
        List<SObject> records,
        Schema.SObjectField externalIdField
    ) {
        return upsertRecords(records, externalIdField, false);
    }
    public virtual List<Database.UpsertResult> upsertRecords(
        List<SObject> records,
        Schema.SObjectField externalIdField,
        Boolean allOrNone
    ) {
        return externalIdField != null
            ? System.Database.upsert(records, externalIdField, allOrNone)
            : System.Database.upsert(records, allOrNone);
    }
    public virtual List<Database.UpsertResult> upsertRecords(
        List<SObject> records,
        Boolean allOrNone,
        System.AccessLevel accessLevel
    ) {
        return upsertRecords(records, null, allOrNone, accessLevel);
    }
    public virtual List<Database.UpsertResult> upsertRecords(
        List<SObject> records,
        Schema.SObjectField externalIdField,
        Boolean allOrNone,
        System.AccessLevel accessLevel
    ) {
        return externalIdField != null
            ? System.Database.upsert(
                  records,
                  externalIdField,
                  allOrNone,
                  accessLevel
              )
            : System.Database.upsert(records, allOrNone, accessLevel);
    }
    // delete - single SObject
    public virtual Database.DeleteResult deleteRecords(SObject record) {
        return deleteRecords(record, false);
    }
    public virtual Database.DeleteResult deleteRecords(
        SObject record,
        Boolean allOrNone
    ) {
        return System.Database.delete(record, allOrNone);
    }
    public virtual Database.DeleteResult deleteRecords(
        SObject record,
        Boolean allOrNone,
        System.AccessLevel accessLevel
    ) {
        return System.Database.delete(record, allOrNone, accessLevel);
    }
    // delete - single Id
    public virtual Database.DeleteResult deleteRecords(Id recordId) {
        return deleteRecords(recordId, false);
    }
    public virtual Database.DeleteResult deleteRecords(
        Id recordId,
        Boolean allOrNone
    ) {
        return System.Database.delete(recordId, allOrNone);
    }
    public virtual Database.DeleteResult deleteRecords(
        Id recordId,
        Boolean allOrNone,
        System.AccessLevel accessLevel
    ) {
        return System.Database.delete(recordId, allOrNone, accessLevel);
    }
    // delete - list SObject
    public virtual List<Database.DeleteResult> deleteRecords(
        List<SObject> records
    ) {
        return deleteRecords(records, false);
    }
    public virtual List<Database.DeleteResult> deleteRecords(
        List<SObject> records,
        Boolean allOrNone
    ) {
        return System.Database.delete(records, allOrNone);
    }
    public virtual List<Database.DeleteResult> deleteRecords(
        List<SObject> records,
        Boolean allOrNone,
        System.AccessLevel accessLevel
    ) {
        return System.Database.delete(records, allOrNone, accessLevel);
    }
    // delete - list Id
    public virtual List<Database.DeleteResult> deleteRecords(
        List<Id> recordIds
    ) {
        return deleteRecords(recordIds, false);
    }
    public virtual List<Database.DeleteResult> deleteRecords(
        List<Id> recordIds,
        Boolean allOrNone
    ) {
        return System.Database.delete(recordIds, allOrNone);
    }
    public virtual List<Database.DeleteResult> deleteRecords(
        List<Id> recordIds,
        Boolean allOrNone,
        System.AccessLevel accessLevel
    ) {
        return System.Database.delete(recordIds, allOrNone, accessLevel);
    }
    // undelete - single SObject
    public virtual Database.UndeleteResult undeleteRecords(SObject record) {
        return undeleteRecords(record, false);
    }
    public virtual Database.UndeleteResult undeleteRecords(
        SObject record,
        Boolean allOrNone
    ) {
        return System.Database.undelete(record, allOrNone);
    }
    public virtual Database.UndeleteResult undeleteRecords(
        SObject record,
        Boolean allOrNone,
        System.AccessLevel accessLevel
    ) {
        return System.Database.undelete(record, allOrNone, accessLevel);
    }
    // undelete - single Id
    public virtual Database.UndeleteResult undeleteRecords(Id recordId) {
        return undeleteRecords(recordId, false);
    }
    public virtual Database.UndeleteResult undeleteRecords(
        Id recordId,
        Boolean allOrNone
    ) {
        return System.Database.undelete(recordId, allOrNone);
    }
    public virtual Database.UndeleteResult undeleteRecords(
        Id recordId,
        Boolean allOrNone,
        System.AccessLevel accessLevel
    ) {
        return System.Database.undelete(recordId, allOrNone, accessLevel);
    }
    // undelete - list SObject
    public virtual List<Database.UndeleteResult> undeleteRecords(
        List<SObject> records
    ) {
        return undeleteRecords(records, false);
    }
    public virtual List<Database.UndeleteResult> undeleteRecords(
        List<SObject> records,
        Boolean allOrNone
    ) {
        return System.Database.undelete(records, allOrNone);
    }
    public virtual List<Database.UndeleteResult> undeleteRecords(
        List<SObject> records,
        Boolean allOrNone,
        System.AccessLevel accessLevel
    ) {
        return System.Database.undelete(records, allOrNone, accessLevel);
    }
    // undelete - list Id
    public virtual List<Database.UndeleteResult> undeleteRecords(
        List<Id> recordIds
    ) {
        return undeleteRecords(recordIds, false);
    }
    public virtual List<Database.UndeleteResult> undeleteRecords(
        List<Id> recordIds,
        Boolean allOrNone
    ) {
        return System.Database.undelete(recordIds, allOrNone);
    }
    public virtual List<Database.UndeleteResult> undeleteRecords(
        List<Id> recordIds,
        Boolean allOrNone,
        System.AccessLevel accessLevel
    ) {
        return System.Database.undelete(recordIds, allOrNone, accessLevel);
    }

    private class MockProxyException extends Exception {
    }
}
