/**
 * @description A base-level implementation of DataWriter where all methods are virtual and overridable
 * by an extending class.
 */
global inherited sharing virtual class DataWriterBase implements DataInterfaces.Writer {
    private final Schema.SObjectType sobjectType;
    /** @constructor */
    global DataWriterBase(Schema.SObjectType sobjectType) {
        this.sobjectType = sobjectType;
    }

    global Schema.SObjectType handlesType() {
        return this.sobjectType;
    }

    global virtual List<Database.SaveResult> insertRecords(
        List<SObject> records
    ) {
        return Database.insert(records);
    }

    global virtual List<Database.SaveResult> updateRecords(
        List<SObject> records
    ) {
        return Database.update(records);
    }

    global virtual List<Database.UpsertResult> upsertRecords(
        List<SObject> records
    ) {
        return Database.upsert(records);
    }

    global virtual List<Database.DeleteResult> deleteRecords(
        List<SObject> records
    ) {
        return Database.delete(records);
    }

    global virtual List<Database.UndeleteResult> undeleteRecords(
        List<SObject> records
    ) {
        return Database.undelete(records);
    }
}
