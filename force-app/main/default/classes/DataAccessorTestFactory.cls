@isTest
/**
 * @description A factory class for unit tests that need to generate DataAccessor instances. This class includes
 * unit tests for itself at the bottom (tagged with @isTest);
 */
global inherited sharing class DataAccessorTestFactory {
    private static Map<Schema.SObjectType, Integer> recordIdCounter = new Map<Schema.SObjectType, Integer>();

    private static void setId(SObject record) {
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
        record.Id = fauxId;
    }

    global static DataAccessorTestFactory.Accessor init(
        Schema.SObjectType sobjectType
    ) {
        return new Accessor(sobjectType);
    }

    global class Accessor implements DataAccessor {
        private List<SObject> records = new List<SObject>();
        private Schema.SObjectType sobjectType;
        private String sobjectTypeString;
        private List<Schema.ChildRelationship> children;
        // more performant than round-trip serialization / deserialization
        private Map<Integer, ChildRecords> childMap = new Map<Integer, ChildRecords>();
        /** @constructor */
        private Accessor(Schema.SObjectType sobjectType) {
            this.sobjectType = sobjectType;
            this.sobjectTypeString = sobjectType.getDescribe().getName();
            this.children = sobjectType.getDescribe().getChildRelationships();
        }

        global Schema.SObjectType readsType() {
            return this.sobjectType;
        }

        global List<SObject> read() {
            return this.records;
        }

        global Accessor addRoot(SObject record) {
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

        global Accessor relateParent(
            SObject parent,
            Schema.SObjectField field
        ) {
            return relateParent(parent, field, this.records.size() - 1);
        }

        global Accessor relateParent(
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

        global Accessor relateChild(SObject child) {
            return relateChild(child, this.records.size() - 1);
        }

        global Accessor relateChild(SObject child, Integer rootRecordPosition) {
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
    private static void testThyself() {
        String ACCOUNT_NAME = 'TestAccount';
        String CASE_SUBJECT = 'Test Case';
        Accessor accessor = init(Schema.Contact.getSObjectType());
        accessor.addRoot(new Contact(LastName = 'Goodtest'));
        accessor.relateChild(new Case(Subject = CASE_SUBJECT));
        accessor.relateChild(new Case(Subject = CASE_SUBJECT));
        accessor.relateParent(
            new Account(Name = ACCOUNT_NAME),
            Schema.Contact.AccountId
        );
        // ensure casting and references work as expected
        Contact c = (Contact) accessor.read()[0];
        System.debug('\n' + JSON.serializePretty(c));
        Assert.areEqual(ACCOUNT_NAME, c.Account.Name);
        Assert.areEqual(2, c.Cases.size());
        Assert.areEqual(CASE_SUBJECT, c.Cases.get(0).Subject);
    }
}
