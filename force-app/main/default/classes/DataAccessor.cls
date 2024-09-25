/**
 * @description A simple interface whose sole job is reading records of a single (root) SObectType from the database.
 * Makes dependency injection and mocking easy so that unit tests can minimize database calls and overhead.
 */
global interface DataAccessor {
    Schema.SObjectType readsType();
    List<SObject> read();
}
