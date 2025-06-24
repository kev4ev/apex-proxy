/**
 * @description Provides APIs for trapping database reads and writes and assignment operands.
 * Provided under the MIT License github.com/kev4ev/apex-proxy
 */

global virtual inherited sharing class Proxy {
    /**
     * @description singleton instance that can only be set (externally) during test execution
     */
    global static Proxy singleton {
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
                // null ns defaults to package ns or 'c' when unpackaged
                try {
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
     * TOP-LEVEL APIS: .reflect() and .db "namespace"
     ***********************/

    /**********************
     * REFLECT API
     ***********************/

    /** @description a simple API for trapping and reflecting values in setters */
    global static Object reflect(Object value) {
        return reflect(value, null);
    }

    /**
     * @description a simple API for trapping and reflecting values in setters, including
     * a key to indicate what value is being trapped.
     */
    global static Object reflect(Object value, String key) {
        return singleton.trap(value, key);
    }

    /**********************
     * db "namespace"
     ***********************/

    global static final Db db = new Db();

    global interface DbReader {
        List<SObject> read(Object readContext);
    }

    global class Db {
        private Db() {
        }

        /**********************
         * READ API
         ***********************/

        global List<SObject> read(DbReader reader) {
            return this.read(reader, null);
        }

        global List<SObject> read(DbReader reader, Object readContext) {
            return singleton.read(reader, readContext);
        }

        /**********************
         * WRITE API
         ***********************/

        global List<Database.SaveResult> insertRecords(List<SObject> records) {
            return singleton.insertRecords(records);
        }
        global List<Database.SaveResult> updateRecords(List<SObject> records) {
            return singleton.updateRecords(records);
        }
        global List<Database.UpsertResult> upsertRecords(
            List<SObject> records
        ) {
            return singleton.upsertRecords(records);
        }
        global List<Database.DeleteResult> deleteRecords(
            List<SObject> records
        ) {
            return singleton.deleteRecords(records);
        }
        global List<Database.UndeleteResult> undeleteRecords(
            List<SObject> records
        ) {
            return singleton.undeleteRecords(records);
        }
    }

    /*********************************
     * SINGLETON OVERRIDEABLE METHODS
     *********************************/

    /**
     * @description reflect API implementation - allows you to trap a value
     * at any point in code execution and introspect its value, along with an
     * optional key indicating what value is being passed.
     */
    global virtual Object trap(Object value, String key) {
        return value;
    }

    /** @description db.read() implementation */
    global virtual List<SObject> read(DbReader reader, Object readContext) {
        return reader.read(readContext);
    }

    /** @description db.insertRecords() implementation */
    global virtual List<Database.SaveResult> insertRecords(
        List<SObject> records
    ) {
        return System.Database.insert(records);
    }

    /** @description db.updateRecords() implementation */
    global virtual List<Database.SaveResult> updateRecords(
        List<SObject> records
    ) {
        return System.Database.update(records);
    }

    /** @description db.upsertRecords() implementation */
    global virtual List<Database.UpsertResult> upsertRecords(
        List<SObject> records
    ) {
        return System.Database.upsert(records);
    }

    /** @description db.deleteRecords() implementation */
    global virtual List<Database.DeleteResult> deleteRecords(
        List<SObject> records
    ) {
        return System.Database.delete(records);
    }

    /** @description db.undeleteRecords() implementation */
    global virtual List<Database.UndeleteResult> undeleteRecords(
        List<SObject> records
    ) {
        return System.Database.undelete(records);
    }

    /**********************
     * HELPER METHODS
     ***********************/
    protected String getClassName(Proxy.DbReader reader) {
        return String.valueOf(reader).split(':')[0]; // todo - includes top-level for inner classes?
    }
}
