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
     * @description A simple interface whose sole job is reading records from the database.
     * Makes dependency injection and mocking easy so that unit tests can minimize database calls and overhead.
     */
    global interface Reader {
        List<SObject> read();
    }

    /**
     * @description A simple interface whose sole job is writing records to the database. Makes dependency injection
     * and mocking easy so that unit tests can minimize database calls and overhead.
     */
    global interface Writer {
        List<Database.SaveResult> insertRecords(List<SObject> records);
        List<Database.SaveResult> updateRecords(List<SObject> records);
        List<Database.UpsertResult> upsertRecords(List<SObject> records);
        List<Database.DeleteResult> deleteRecords(List<SObject> records);
        List<Database.UndeleteResult> undeleteRecords(List<SObject> records);
    }

    /**
     * @description A base-level implementation of DataInterfaces.Writer. All methods are virtual and as such
     * overridable by an extending class. Veneer over the Database class methods.
     */
    global inherited sharing virtual class VirtualWriter implements Writer {
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

    global interface MethodProxy {
        MethodProxy call(String classMethodReference);
        MethodProxy call(String classMethodReference, List<Object> args);
    }
}
