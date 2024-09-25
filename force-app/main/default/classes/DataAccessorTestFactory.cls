@isTest
global inherited sharing class DataAccessorTestFactory {
    private DataAccessorTestFactory() {
        // static-only access
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

        global Accessor relateChild(SObject child) {
            return relateChild(child, this.records.size() - 1);
        }

        global Accessor relateChild(SObject child, Integer rootRecordPosition) {
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

            // TODO support multiple children
            setRootFieldDynamic(
                rootRecordPosition,
                relationshipName,
                JSON.deserialize(
                    JSON.serialize(new List<SObject>{ child }),
                    List<SObject>.class
                )
            );

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
            String rawName = field.getDescribe().getName();
            String relName = rawName.endsWith('__c')
                ? rawName.replace('__c', '__r')
                : rawName.replace('Id', '');
            setRootFieldDynamic(rootRecordPosition, relName, parent);
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

    private class AccessorException extends Exception {
    }

    @isTest
    private static void testThyself() {
        Accessor accessor = init(Schema.Contact.getSObjectType());
        accessor.addRoot(new Contact(LastName = 'Goodtest'));
        // accessor.relateChild(new Case(Subject = 'Test Case')); TODO get working
        accessor.relateParent(
            new Account(Name = 'Test Account'),
            Schema.Contact.AccountId
        );
        // ensure casting works
        Contact c = (Contact) accessor.read()[0];
        System.debug(JSON.serializePretty(c));
        Account a = new Account(Name = 'tim');
        insert a;
        insert new Contact(LastName = 'jim', AccountId = a.Id);
        System.debug(
            JSON.serializePretty(
                [
                    SELECT Id, (SELECT LastName FROM Contacts)
                    FROM Account
                    LIMIT 1
                ]
            )
        );
    }
}
