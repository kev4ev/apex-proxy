@isTest
private with sharing class DbReaderExampleTest extends TestProxy.Base {
    private static Integer expectedContacts;
    private static Id expectedAcctId;
    private static String expectedUid;

    @isTest
    private static void validate_db_operation() {
        // insert Account and child Contacts
        Account a = new Account(Name = 'Test Acct');
        insert a;
        String uid = UUID.randomUUID().toString();
        List<Contact> contacts = initContacts(10, uid, a.Id);
        insert contacts;
        // get Account and Contacts without mocking
        Account ctrlAcct = DbReaderExample.getAccountContacts(a.Id.toString());
        validateAssertions(ctrlAcct);
    }

    @isTest
    private static void validate_dbReader_mock() {
        // insert Account and child Contacts
        Account a = new Account(Name = 'Test Acct');
        insert a;
        String uid = UUID.randomUUID().toString();
        List<Contact> contacts = initContacts(10, uid, a.Id);
        insert contacts;
        // set test singleton
        Proxy.singleton = new DbReaderExampleTest();
        // TODO mock return
        // assert null returned now
        Assert.isNull(
            DbReaderExample.getAccountContacts(a.Id),
            'Should be null'
        );
    }

    /** @description Proxy.DbReader implementation */
    public override List<SObject> read(DbReader reader, Object readContext) {
        // check the type of incoming reader
        System.debug('ClassName:' + getClassName(reader));
        return null;
    }

    private static List<Contact> initContacts(Integer numContacts, String uid) {
        return initContacts(numContacts, uid, null);
    }
    private static List<Contact> initContacts(
        Integer numContacts,
        String uid,
        Id accountId
    ) {
        // set static values for assertions
        expectedContacts = numContacts;
        expectedUid = uid;
        expectedAcctId = accountId;
        // init and return contacts
        List<Contact> contacts = new List<Contact>();
        for (Integer i = 0, k = 10; i < k; i++) {
            contacts.add(
                new Contact(
                    FirstName = 'Michael',
                    Title = uid,
                    LastName = 'Scott' + i.toString(),
                    AccountId = accountId
                )
            );
        }

        return contacts;
    }

    private static void validateAssertions(Account acct) {
        Assert.areEqual(expectedAcctId, acct.Id);
        Assert.areEqual(expectedContacts, acct.Contacts.size());
        Integer ctr = 0;
        for (Contact c : acct.Contacts) {
            Assert.areEqual(expectedUid, c.Title);
            Assert.areEqual('Scott' + ctr.toString(), c.LastName);
            ctr += 1;
        }
    }
}
