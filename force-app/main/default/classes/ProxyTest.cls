/**
 * @description Unit tests covering Proxy reflect, db, and mock APIs.
 * Provided under the MIT License github.com/kev4ev/apex-proxy
 */

@isTest
public inherited sharing class ProxyTest extends Proxy.MockReader {
    private static final String ACCT_NAME = 'Root Account ';
    private static final String PARENT_NAME = 'Parent Account';
    private static final String CT_FNAME = 'Child';
    private static final String CT_LNAME = 'Contact ';

    private static String reflected;
    private static String readerClassName;

    /** @description Proxy.MockReader implementation */
    public override List<SObject> read(Object ctx) {
        return [
            SELECT Id, Parent.Name, (SELECT FirstName, LastName FROM Contacts)
            FROM Account
        ];
    }

    /********************************************
     * VALIDATE REFLECT API
     *********************************************/

    @isTest
    private static void validateDefaultProxyIsSingleton() {
        // override DEF_PROXY and assert singleton is properly assigned
        Proxy.DEF_PROXY = 'TestProxy.Base';
        Assert.isTrue(Proxy.singleton instanceof TestProxy.Base);
        // reset and test again
        Proxy.singleton = null;
        Proxy.DEF_PROXY = '';
        Assert.isNotNull(Proxy.singleton);
    }

    /********************************************
     * VALIDATE DB API
     *********************************************/

    @isTest
    private static void coverProxyDbOperations() {
        List<Account> accts = new List<Account>();
        Assert.areEqual(0, Proxy.db.insertRecords(accts).size());
        Assert.areEqual(0, Proxy.db.updateRecords(accts).size());
        Assert.areEqual(0, Proxy.db.upsertRecords(accts).size());
        Assert.areEqual(0, Proxy.db.deleteRecords(accts).size());
        Assert.areEqual(0, Proxy.db.undeleteRecords(accts).size());
    }

    /********************************************
     * VALIDATE MOCK API
     *********************************************/

    /********************************************
     * VALIDATE MOCK API: declarative API approach
     *********************************************/
    @isTest
    private static void validateMockSingletons() {
        // assert default proxy before mocking
        Assert.isFalse(Proxy.singleton instanceof Proxy.Mock);
        // assert now mocking desired types
        Proxy.mock();
        Assert.isTrue(Proxy.singleton instanceof Proxy.Mock);
        Proxy.mock(new CustomMock());
        Assert.areEqual(
            'CustomMock',
            Proxy.introspectName(Proxy.mockSingleton)
        );
        Assert.isTrue(Proxy.mockSingleton instanceof CustomMock);
        Assert.isTrue(Proxy.singleton instanceof CustomMock);
    }

    @isTest
    private static void reflect_validateTrap() {
        Proxy.mock();
        Integer trapped = (Integer) Proxy.reflect(42, 'int');
        Assert.areEqual(42, (Integer) Proxy.mock.trapAudit.get('int'));
    }

    @isTest
    private static void db_coverWrite() {
        Proxy.mock();
        coverProxyDbOperations();
    }

    @isTest
    private static void dbRead_validateMockRead() {
        Proxy.mock()
            .mockReader(ProxyTest.class)
            .addReadRecord(Proxy.mock.setFauxId(new Account()));

        // assert "clean mode": 1 account returned and each read returns a clone of the read record
        ProxyTest reader = new ProxyTest();
        Account a0 = (Account) Proxy.db.read(reader)[0];
        Assert.isNotNull(a0.Id);
        a0.Name = 'Modified In-Memory';
        Account a1 = (Account) Proxy.db.read(reader)[0];
        Assert.areEqual(a0.Id, a1.Id);
        Assert.isNull(a1.Name);

        // validate the readAudit
        Account audit0 = ((Account) Proxy.mock.readAudit.get('proxytest')
            .get(0)
            .get(0));
        Account audit1 = ((Account) Proxy.mock.readAudit.get('proxytest')
            .get(1)
            .get(0));
        Assert.isNotNull(audit0.Name);
        Assert.isNull(audit1.Name);
    }

    /********************************************
     * VALIDATE MOCK API: class override approach
     *********************************************/

    private class MockTarget implements Proxy.DbReader {
        public String readStateArg;

        public List<Account> getAccountsAndChildren() {
            return (List<Account>) Proxy.db.read(this);
        }

        public List<SObject> read(Object ctx) {
            this.readStateArg = (String) Proxy.reflect(ctx);
            return [
                SELECT
                    Id,
                    Parent.Name,
                    (SELECT FirstName, LastName FROM Contacts)
                FROM Account
            ];
        }
    }

    private class CustomMock extends Proxy.Mock {
        public override Object trap(Object value, String key) {
            String changeReflection = UUID.randomUUID().toString();
            reflected = changeReflection;
            trapAudit(value, key);

            return changeReflection;
        }

        public override List<SObject> read(Proxy.DbReader reader, Object ctx) {
            // capture classname for assertion
            readerClassName = getClassName(reader);

            Proxy.MockReader mockRead = new Proxy.MockReader();
            // return 5 Accounts that each have a parent and 5 child Contacts
            mockRead.addReadRecord(new Account());
            mockRead.relateParent(
                new Account(Name = PARENT_NAME),
                Schema.Account.ParentId
            );
            for (Integer i = 0, k = 5; i < k; i++) {
                mockRead.relateChild(
                    new Contact(
                        FirstName = CT_FNAME,
                        LastName = CT_LNAME + i.toString()
                    )
                );
            }
            String positionReplacement = '<replace>';
            mockRead.repeat(
                5,
                new Map<Schema.SObjectField, Object>{
                    Schema.Account.Name => ACCT_NAME +
                    positionReplacement // set name here to test replacement
                },
                positionReplacement
            );

            List<SObject> readRecords = mockRead.read(ctx);
            readAudit(readerClassName, readRecords);

            return readRecords;
        }
    }

    @isTest
    /**
     * @description Validates that the reflection API:
     *   (1) returns the passed-in value when not mocked
     *   (2) returns the mocked value when mocked
     */
    private static void validateReflectionIntercept() {
        // validate normal reflection
        MockTarget target = new MockTarget();
        String original = 'someContext';
        target.read(original);
        Assert.areEqual(original, target.readStateArg);
        // validate mocking works as expected
        Proxy.singleton = new CustomMock();
        target.read(original);
        Assert.areEqual(reflected, target.readStateArg);
    }

    @isTest
    /**
     * @description Validates that the reader api:
     *   (1) invokes the passed-in reader when not mocked, returning the expected result
     *   (2) utilizes the mock singleton and returns the mocked response
     */
    private static void validateDbReaderIntercept() {
        // assert no results in actual test db
        MockTarget target = new MockTarget();
        Assert.areEqual(0, target.getAccountsAndChildren().size());
        // mock and assert the results
        Proxy.singleton = new CustomMock();
        List<Account> mockResults = target.getAccountsAndChildren();
        // assert expected shape
        Assert.areEqual(5, mockResults.size());
        for (Integer i = 0, k = mockResults.size(); i < k; i++) {
            Account a = mockResults[i];
            Assert.areEqual(ACCT_NAME + i.toString(), a.Name);
            Assert.areEqual(PARENT_NAME, a.Parent.Name);
            for (Integer c = 0, j = a.Contacts.size(); c < j; c++) {
                Contact ct = a.Contacts.get(c);
                Assert.areEqual(CT_FNAME, ct.FirstName);
                Assert.areEqual(CT_LNAME + c.toString(), ct.LastName);
            }
        }
    }

    @isTest
    /**
     * @description Validates that Proxy.DbReader classname introspection returns as expected.
     */
    private static void validateIntrospectClassname() {
        // set singleton mock and invoke target
        Proxy.singleton = new CustomMock();
        new MockTarget().getAccountsAndChildren();
        Assert.areEqual('MockTarget', readerClassName); // inner class name, but won't print
    }

    @isTest
    /**
     * @description Validates that a configured default proxy is used when configured
     */
    private static void validateDefaultProxyRespected() {
        String orgDefault;
        try {
            orgDefault = System.Label.get(null, 'DefaultProxy');
        } catch (Exception e) {
            orgDefault = '';
        }
        Assert.areEqual(orgDefault, Proxy.DEF_PROXY);
    }
}
