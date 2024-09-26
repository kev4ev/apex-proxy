/**
 * @description An interface whose jobe is accessing data of a given SObjectType. Composes DataReader and DataWriter
 * functionality for simplified usage.
 */
global interface DataAccessor {
    DataReader getReader();
    DataWriter getWriter();
}
