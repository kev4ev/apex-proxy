/**
 * @description Provides a pseudo-namespaced collection of the extendable types in the library.
 */
global inherited sharing class Proxies {
    @testVisible
    /**
     * @description TestVisible as constructor requires coverage
     * @constructor
     */
    private Proxies() {
    }

    /**
     * @description A simple interface whose sole job is reading records from the database.
     */
    global interface DbRead {
        List<SObject> read();
    }

    /**
     * @description A simple interface whose sole job is writing records to the database.
     */
    global interface DbWrite {
        List<Database.SaveResult> insertRecords(List<SObject> records);
        List<Database.SaveResult> updateRecords(List<SObject> records);
        List<Database.UpsertResult> upsertRecords(List<SObject> records);
        List<Database.DeleteResult> deleteRecords(List<SObject> records);
        List<Database.UndeleteResult> undeleteRecords(List<SObject> records);
    }

    /**
     * @description Proxy to a method call or property of an apex type (class) defined by the
     * string that accesses it. Enables easy stubbing of class dependencies that are
     * troublesome to isolate in unit tests.
     */
    global interface TypeAccessor {
        Object call(String accessPath);
        Object call(String accessPath, List<Object> args);
    }

    /**
     * @description A convenience implementation of DbWrite that is just a veneer over Database class methods.
     * Default implementation is suitable for most use cases but all methods are virtual so as to be overridable
     * by an extending class.
     */
    global inherited sharing virtual class VirtualWriter implements DbWrite {
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
}
