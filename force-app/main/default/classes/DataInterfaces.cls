/**
 * @description Provides a pseudo-namespaced collection of the data interfaces in the library.
 */
global inherited sharing class DataInterfaces {
    @testVisible
    /**
     * @description TestVisible as constructor requires coverage
     * @constructor
     */
    private DataInterfaces() {
    }
    /**
     * @description An interface whose jobe is accessing data of a given SObjectType. Composes DataReader and DataWriter
     * functionality for simplified usage.
     */
    global interface Accessor {
        Reader getReader();
        Writer getWriter();
    }

    /**
     * @description A simple interface whose sole job is reading records of a single (root) SObectType from the database.
     * Makes dependency injection and mocking easy so that unit tests can minimize database calls and overhead.
     */
    global interface Reader {
        Schema.SObjectType handlesType();
        List<SObject> read();
    }

    /**
     * @description A simple interface whose sole job is writing records to the database. May handle more than one
     * SObjectType. Makes dependency injection and mocking easy so that unit tests can minimize database calls
     * and overhead.
     */
    global interface Writer {
        List<Schema.SObjectType> handlesTypes();
        List<Database.SaveResult> insertRecords(List<SObject> records);
        List<Database.SaveResult> updateRecords(List<SObject> records);
        List<Database.UpsertResult> upsertRecords(List<SObject> records);
        List<Database.DeleteResult> deleteRecords(List<SObject> records);
        List<Database.UndeleteResult> undeleteRecords(List<SObject> records);
    }
}
