@isTest
/**
 * @description A factory class for unit test proxies. Includes:
 *   1. DbRead proxy with a declarative builder api,
 *   2. DbWrite proxy with default implementation that does not hit the database,
 *   3. TypeAccessor proxy
 *
 * All 3 proxies also include an asTestStub() method that accepts a StubProvider instance
 * that will receive passthrough control during method invocation.
 * Provided under the MIT License, Copyright 2024 kev4ev/apex-proxy.
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

    global static ProxyTestFactory.DbRead initDbRead() {
        return new DbRead();
    }

    global static ProxyTestFactory.DbWrite initDbWrite() {
        return new DbWrite();
    }

    global static Object initTypeAccessorStub(
        System.Type typeAccessorToMock,
        StubCallbackController controller
    ) {
        return new TypeAccessor()
            .createTestStub(typeAccessorToMock, controller);
    }

    global class DbRead extends Proxy implements Proxies.DbRead {
        global Boolean testLimits = false;
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
            if (this.testLimits == true) {
                Integer cnt = [SELECT COUNT() FROM Account LIMIT 1];
            }
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

        /**
         * Appends the current record to the read list the given number of times INCLUDING the current record.
         * @param {Integer} number of times to repeat the current record
         * @return {DbRead} this instance for chaining
         */
        global DbRead repeat(Integer repeatCount) {
            return repeat(repeatCount, null);
        }

        /**
         * Appends the current record to the read list the given number of times INCLUDING the current record,
         * replacing the strings provided.
         * @param {Integer} number of times to repeat the current record
         * @param {Map<Schema.SObjectField, String>} a map of fields to the strings that will be written to each
         * record. Strings will have the following sequences replaced:
         *  - {0}: the repeated item number, starting from 1 (the original record should be treated as 0)
         * @return {DbRead} this instance for chaining
         */
        global DbRead repeat(
            Integer repeatCount,
            Map<Schema.SObjectField, String> replacements
        ) {
            List<SObject> records = getBuildtimeStepRecords();
            SObject curr = records.get(records.size() - 1);
            for (Integer i = 0; i < repeatCount; i++) {
                // first iteration the target is curr itself so that repeat count is inclusive of the original
                SObject target = i == 0 ? curr : curr.clone(false, true);
                if (replacements != null && replacements.size() > 0) {
                    List<Object> replaceWith = new List<Object>{ i };
                    for (Schema.SObjectField sof : replacements.keySet()) {
                        replaceAndWrite(
                            target,
                            sof,
                            replacements.get(sof),
                            replaceWith
                        );
                    }
                }
                if (i > 0) {
                    addRoot(target);
                }
            }

            return this;
        }

        private void replaceAndWrite(
            SObject record,
            Schema.SObjectField field,
            String replacee,
            List<Object> replacements
        ) {
            record.put(field, String.format(replacee, replacements));
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

        /**
         * When invoked, a minimal overhead query will be executed for each call to read() such
         * that limits testing can be simulated. Note that otal queries can be simulated but rows
         * retrieved cannot.
         */
        global DbRead testLimits() {
            this.testLimits = true;

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

    global virtual class DbWrite extends Proxy implements Proxies.DbWrite {
        global Boolean testLimits = false;

        global virtual List<Database.SaveResult> insertRecords(
            List<SObject> records
        ) {
            handleLimits();
            // do nothing
            return null;
        }

        global virtual List<Database.SaveResult> updateRecords(
            List<SObject> records
        ) {
            handleLimits();
            // do nothing
            return null;
        }

        global virtual List<Database.UpsertResult> upsertRecords(
            List<SObject> records
        ) {
            handleLimits();
            // do nothing
            return null;
        }

        global virtual List<Database.DeleteResult> deleteRecords(
            List<SObject> records
        ) {
            handleLimits();
            // do nothing
            return null;
        }

        global virtual List<Database.UndeleteResult> undeleteRecords(
            List<SObject> records
        ) {
            handleLimits();
            // do nothing
            return null;
        }

        /**
         * When invoked, a savepoint will be set for each call to a dml method (which counts as a dml statement),
         * such that limits testing can be simulated. Note that total dml statements can be
         * simulated but dml rows cannot.
         */
        global DbWrite testLimits() {
            this.testLimits = true;

            return this;
        }

        private void handleLimits() {
            if (this.testLimits == true) {
                Database.setSavepoint();
            }
        }
    }

    global virtual class TypeAccessor extends Proxy implements Proxies.TypeAccessor {
        global virtual Object call(String accessPath) {
            throw new FactoryException(
                'Caller must either implement the call() method or use as a test stub'
            );
        }

        global virtual Object call(String accessPath, List<Object> args) {
            throw new FactoryException(
                'Caller must either implement the call() method or use as a test stub'
            );
        }
    }

    global abstract class Proxy {
        global System.StubProvider asCallbackStub(
            StubCallbackController controller
        ) {
            return new StubPassthrough(controller, this);
        }

        global Object createTestStub(
            System.Type typeToMock,
            StubCallbackController controller
        ) {
            return Test.createStub(
                typeToMock,
                new StubPassthrough(controller, this)
            );
        }
    }

    global interface StubCallbackController {
        Object handleMethodCall(
            Object stubbedObject,
            String stubbedMethodName,
            System.Type returnType,
            List<System.Type> listOfParamTypes,
            List<String> listOfParamNames,
            List<Object> listOfArgs,
            Proxy callingProxy
        );
    }

    private class StubPassthrough implements System.StubProvider {
        private StubCallbackController controller;
        private Proxy originatingProxy;
        public StubPassthrough(
            StubCallbackController controller,
            Proxy originatingProxy
        ) {
            this.controller = controller;
            this.originatingProxy = originatingProxy;
        }

        public Object handleMethodCall(
            Object stubbedObject,
            String stubbedMethodName,
            System.Type returnType,
            List<System.Type> listOfParamTypes,
            List<String> listOfParamNames,
            List<Object> listOfArgs
        ) {
            // pass through to controller for implementation and return of necessary object
            return this.controller.handleMethodCall(
                stubbedObject,
                stubbedMethodName,
                returnType,
                listOfParamTypes,
                listOfParamNames,
                listOfArgs,
                this.originatingProxy
            );
        }
    }

    private class FactoryException extends Exception {
    }
}
