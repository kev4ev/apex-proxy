/**
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

    /**********************
     * TOP-LEVEL APIS: .reflect() and .db "namespace"
     ***********************/

    /**********************
     * REFLECT API
     ***********************/

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

    /**********************
     * db "namespace"
     ***********************/

    public static final Db db = new Db();

    public interface DbReader {
        List<SObject> read(Object readContext);
    }

    public class Db {
        private Db() {
        }

        /**********************
         * READ API
         ***********************/

        public List<SObject> read(DbReader reader) {
            return this.read(reader, null);
        }

        public List<SObject> read(DbReader reader, Object readContext) {
            return singleton.read(reader, readContext);
        }

        /**********************
         * WRITE API
         ***********************/

        public List<Database.SaveResult> insertRecords(List<SObject> records) {
            return singleton.insertRecords(records);
        }
        public List<Database.SaveResult> updateRecords(List<SObject> records) {
            return singleton.updateRecords(records);
        }
        public List<Database.UpsertResult> upsertRecords(
            List<SObject> records
        ) {
            return singleton.upsertRecords(records);
        }
        public List<Database.DeleteResult> deleteRecords(
            List<SObject> records
        ) {
            return singleton.deleteRecords(records);
        }
        public List<Database.UndeleteResult> undeleteRecords(
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
    public virtual Object trap(Object value, String key) {
        return value;
    }

    /** @description db.read() implementation */
    public virtual List<SObject> read(DbReader reader, Object readContext) {
        return reader.read(readContext);
    }

    /** @description db.insertRecords() implementation */
    public virtual List<Database.SaveResult> insertRecords(
        List<SObject> records
    ) {
        return System.Database.insert(records);
    }

    /** @description db.updateRecords() implementation */
    public virtual List<Database.SaveResult> updateRecords(
        List<SObject> records
    ) {
        return System.Database.update(records);
    }

    /** @description db.upsertRecords() implementation */
    public virtual List<Database.UpsertResult> upsertRecords(
        List<SObject> records
    ) {
        return System.Database.upsert(records);
    }

    /** @description db.deleteRecords() implementation */
    public virtual List<Database.DeleteResult> deleteRecords(
        List<SObject> records
    ) {
        return System.Database.delete(records);
    }

    /** @description db.undeleteRecords() implementation */
    public virtual List<Database.UndeleteResult> undeleteRecords(
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
