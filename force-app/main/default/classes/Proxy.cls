/**
 * @description Provides APIs for trapping database reads and writes and assignment operands.
 * Provided under the MIT License github.com/kev4ev/apex-proxy
 */

public virtual inherited sharing class Proxy {
    /************************************
     * SINGLETON AND ITS INTERNAL STATE
     ************************************/
    private Object readContext;

    /** @description singleton instance that can only be set externally during test execution */
    public static Proxy singleton {
        get {
            if (singleton == null) {
                String defaultProxy =
                    /** System.Label.DefaultProxy;  todo */ '';
                singleton = String.isBlank(defaultProxy)
                    ? new Proxy()
                    : (Proxy) Type.forName('c', defaultProxy).newInstance();
            }

            return singleton;
        }
        set {
            if (Test.isRunningTest()) {
                singleton = value;
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
        return singleton.trap(value);
    }

    /**********************
     * db "namespace"
     ***********************/

    public static final Db db = new Db();

    public class Db {
        private Db() {
        }

        /**********************
         * READ API
         ***********************/

        public Db setReadContext(Object readContext) {
            singleton.readContext = readContext;

            return this;
        }

        public List<SObject> read(DbReader reader) {
            List<SObject> result = singleton.read(
                reader,
                singleton.readContext
            );
            // reset the readContext
            singleton.readContext = null;

            return result;
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

    /**********************
     * INTERFACES
     ***********************/

    public interface DbReader {
        List<SObject> read(Object readContext);
    }

    /**********************
     * SINGLETON OVERRIDES
     ***********************/

    /** @description reflect API implementation */
    public virtual Object trap(Object value) {
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
    protected String getClassName(Object toIntrospect) {
        return String.valueOf(toIntrospect).split(':')[0]; // todo - includes top-level for inner classes?
    }
}
