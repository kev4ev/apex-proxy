/**
 * @description A simple interface whose sole job is reading records of a single (root) SObectType from the database.
 * Makes dependency injection and mocking easy so that unit tests can minimize database calls and overhead.
 */
global interface DataWriter {
    Schema.SObjectType handlesType();
    List<Database.SaveResult> insertRecords(List<SObject> records);
    List<Database.SaveResult> updateRecords(List<SObject> records);
    List<Database.UpsertResult> upsertRecords(List<SObject> records);
    List<Database.DeleteResult> deleteRecords(List<SObject> records);
    List<Database.UndeleteResult> undeleteRecords(List<SObject> records);
}
