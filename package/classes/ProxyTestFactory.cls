@isTest
/**
 * @description A factory class for unit test proxies. Includes:
 *   1. DbRead proxy with a declarative builder api,
 *   2. DbWrite proxy with default implementation that does not hit the database,
 *   3. TypeAccessor proxy
 *
 * All 3 proxies also include an asTestStub() method that accepts a StubProvider instance
 * that will receive passthrough control during method invocation.
 */
global inherited sharing class ProxyTestFactory {
    private static Map<Schema.SObjectType, Integer> recordIdCounter = new Map<Schema.SObjectType, Integer>();

    global static SObject setFauxId(SObject record) {
        record.Id = getFauxId(record);

        return record;
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

    global static ProxyTestFactory.DbRead initDbRead(){
        return new DbRead();
    }

    global static ProxyTestFactory.DbWrite initDbWrite(){
        return new DbWrite();
    }

    global static Object initTypeAccessorStub(System.Type typeAccessorToMock, System.StubProvider controller){
        return new TypeAccessor().asTestStub(typeAccessorToMock, controller);
    }

    global class DbRead extends StubPassthrough implements Proxies.DbRead {
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
        private Integer readtimeReadStep = -1; // incremented upon first read()
        private String readtimeCondition;
        private Boolean freezeReadState = false;
        /** @description A callback controller that will be invoked when DbRead is used as a Test stub */
        private System.StubProvider controller;
        /** @constructor */
        private DbRead() {
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
                // increment the read list
                if (!freezeReadState) {
                    this.readtimeReadStep += 1;
                }
                // return the list or null if read steps exhausted
                readList = readtimeReadStep < this.readStepRecords.size()
                    ? this.readStepRecords.get(this.readtimeReadStep)
                    : null;
            }

            // return the results
            return readList;
        }

        global DbRead loopReadStep(Integer step) {
            this.freezeReadState = true;
            Integer max = readStepRecords.size() - 1;
            if (step < 0 || step > max) {
                throw new FactoryException(
                    'Index out of bounds: ' +
                        step.toString() +
                        '; min is 0 and max size is ' +
                        max
                );
            }
            this.readtimeReadStep = step;

            return this;
        }

        global DbRead setReadCondition(String condition) {
            if (!this.readConditionalRecords.keySet().contains(condition)) {
                throw new FactoryException(
                    'Condition ' +
                        condition +
                        ' was never initialized. Use addConditionalRead().'
                );
            }
            this.readtimeCondition = condition;

            return this;
        }

        global DbRead loopReadCondition(String condition) {
            this.freezeReadState = true;

            return setReadCondition(condition);
        }

        global DbRead cancelLoop() {
            this.freezeReadState = false;
            this.readtimeCondition = null;

            return this;
        }

        /********************
         * BUILD-TIME METHODS
         ********************/

        /**
         * Adds a read step that will return a list of records of size 0.
         * @return {DbRead} the reader instance for chaining
         */
        global DbRead addEmptyReadStep() {
            Integer addNew = getBuildtimeStepRecords().isEmpty() ? 1 : 2;
            for (Integer i = 0, k = addNew; i < k; i++) {
                this.readStepRecords.add(new List<SObject>());
            }

            return this;
        }

        /**
         * Add a new read step to the DbRead.
         * @param {SObject} record the root record to initizize the new read step list
         * @return {DbRead} the reader instance for chaining
         */
        global DbRead addReadStep(SObject record) {
            // ensure current list is not empty
            if (getBuildtimeStepRecords().isEmpty()) {
                throw new FactoryException(
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
         * Add a new read step to the DbRead.
         * @param {SObject} record the root record to initizize the new read step list
         * @param {String} condition the condition that must be set for the record list to return; use
         * setReadCondition() to enable the condition
         * @return {DbRead} the reader instance for chaining
         */
        global DbRead addConditionalRead(SObject record, String condition) {
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
         * @return {DbRead} this instance for chaining
         */
        global DbRead addRoot(SObject record) {
            // set a faux id
            setFauxId(record);
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
                throw new FactoryException(
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

        global DbRead relateChild(SObject child) {
            return relateChild(child, getCurrentBuildtimeRecords().size() - 1);
        }

        global DbRead relateChild(SObject child, Integer rootRecordPosition) {
            // set faux id
            setFauxId(child);
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
                throw new FactoryException(
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

        global DbRead relateParent(SObject parent, Schema.SObjectField field) {
            return relateParent(
                parent,
                field,
                getCurrentBuildtimeRecords().size() - 1
            );
        }

        global DbRead relateParent(
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
            // delegate field set and return self
            setRootFieldDynamic(rootRecordPosition, relName, parent);

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

    global virtual class DbWrite extends StubPassthrough implements Proxies.DbWrite {
        global virtual List<Database.SaveResult> insertRecords(
            List<SObject> records
        ) {
            // do nothing
            return null;
        }

        global virtual List<Database.SaveResult> updateRecords(
            List<SObject> records
        ) {
            // do nothing
            return null;
        }

        global virtual List<Database.UpsertResult> upsertRecords(
            List<SObject> records
        ) {
            // do nothing
            return null;
        }

        global virtual List<Database.DeleteResult> deleteRecords(
            List<SObject> records
        ) {
            // do nothing
            return null;
        }

        global virtual List<Database.UndeleteResult> undeleteRecords(
            List<SObject> records
        ) {
            // do nothing
            return null;
        }
    }

    global virtual class TypeAccessor extends StubPassthrough implements Proxies.TypeAccessor{

        global virtual Object call(String accessPath){
            throw new FactoryException('Caller must either implement the call() method or use as a test stub');
        }

        global virtual Object call(String accessPath, List<Object> args){
            throw new FactoryException('Caller must either implement the call() method or use as a test stub');
        }
    }

    global abstract class StubPassthrough implements System.StubProvider {
        private System.StubProvider controller;

        global Object asTestStub(
            System.Type typeToMock,
            System.StubProvider controller
        ) {
            this.controller = controller;

            return Test.createStub(
                typeToMock,
                this
            );
        }

        public Object handleMethodCall(
            Object stubbedObject,
            String stubbedMethodName,
            System.Type returnType,
            List<System.Type> listOfParamTypes,
            List<String> listOfParamNames,
            List<Object> listOfArgs
        ) {
            // always append self as final item to listOfArgs
            if (listOfArgs == null) {
                listOfArgs = new List<Object>();
            }

            listOfArgs.add(this);

            // pass through to controller for implementation and return of necessary object
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

    private class FactoryException extends Exception {
    }
}