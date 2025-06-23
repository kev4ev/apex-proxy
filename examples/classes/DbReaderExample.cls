public with sharing class DbReaderExample implements Proxy.DbReader {
    public List<Account> read(Object acctId) {
        return [
            SELECT Id, (SELECT FirstName, LastName, Title FROM Contacts)
            FROM Account
            WHERE Id = :((Id) acctId)
        ];
    }

    public static Account getAccountContacts(String acctId) {
        try {
            return ((List<Account>) Proxy.db.setReadContext(acctId)
                    .read(new DbReaderExample()))
                ?.get(0);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}
