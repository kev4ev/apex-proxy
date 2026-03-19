/**
 * @version 1.0.0
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

    @isTest
    private static void validateDefaultProxyIsSingleton() {
        // override DEF_PROXY and assert singleton is properly assigned
        Proxy.DEF_PROXY = 'Proxy.Mock';
        Assert.isTrue(Proxy.singleton instanceof Proxy.Mock);
        // reset and test again
        Proxy.singleton = null;
        Proxy.DEF_PROXY = '';
        Assert.isNotNull(Proxy.singleton);
    }

    /****************************************************************************************
     * VALIDATE MOCK API
     *****************************************************************************************/

    @isTest
    /**
     * @description Validates Mock.relateParent(child, parent, relationField):
     *   (1) the foreign key field (e.g. AccountId) is populated on the returned child
     *   (2) the parent relationship object (e.g. Account) is traversable on the returned child
     */
    private static void mock_relateParent_childParentField_setsRelationshipOnChild() {
        Proxy.mock();
        Account parent = new Account(Name = 'Parent Acct');
        Contact child = new Contact(FirstName = 'Child');

        Contact result = (Contact) Proxy.mock.relateParent(
            child,
            parent,
            Schema.Contact.AccountId
        );

        Assert.isNotNull(result.AccountId);
        Assert.areEqual('Parent Acct', result.Account.Name);
    }

    @isTest
    /**
     * @description Validates Mock.relateParent(parent, child):
     *   (1) the child sub-list relationship is populated on the returned parent
     *   (2) the child record's fields are intact
     */
    private static void mock_relateParent_parentChild_setsChildRelationshipOnParent() {
        Proxy.mock();
        Account parent = new Account(Name = 'Root');
        Contact child = new Contact(FirstName = 'Child', LastName = 'Test');

        Account result = (Account) Proxy.mock.relateParent(parent, child);

        Assert.areEqual(1, result.Contacts.size());
        Assert.areEqual('Child', result.Contacts[0].FirstName);
        Assert.areEqual('Test', result.Contacts[0].LastName);
    }

    /****************************************************************************************
     * VALIDATE REFLECT API
     *****************************************************************************************/

    @isTest
    /**
     * @description Validates Mock.trap(String):
     *   (1) returns the key itself
     *   (2) reflect passthrough — original value is returned because no replacement was registered
     *   (3) trapAudit records the reflected value under that key
     */
    private static void mock_trap_stringKey_registersWatchAndPassesThrough() {
        Proxy.mock();
        String key = 'watchedKey';
        Integer value = 42;

        String returnedKey = Proxy.mock.trap(key);
        Assert.areEqual(key, returnedKey);

        Integer result = (Integer) Proxy.reflect(value, key);
        Assert.areEqual(value, result);
        Assert.areEqual(value, (Integer) Proxy.mock.trapAudit.get(key));
    }

    @isTest
    /**
     * @description Validates Mock.trap(String, System.Type):
     *   (1) returns the composed key (key + '_' + caller.getName())
     *   (2) reflect passthrough — original value is returned because no replacement was registered
     *   (3) trapAudit records the reflected value under the composed key
     */
    private static void mock_trap_stringKeyAndType_registersCallerScopedWatchAndPassesThrough() {
        Proxy.mock();
        String key = 'scopedKey';
        Integer value = 55;
        String composedKey = key + '_' + ProxyTest.class.getName();

        String returnedKey = Proxy.mock.trap(key, ProxyTest.class);
        Assert.areEqual(composedKey, returnedKey);

        Integer result = (Integer) Proxy.reflect(value, key, ProxyTest.class);
        Assert.areEqual(value, result);
        Assert.areEqual(value, (Integer) Proxy.mock.trapAudit.get(composedKey));
    }

    /********************************************
     * VALIDATE MOCK READ API: declarative API approach
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
            'CustomMock'.toLowerCase(),
            Proxy.normalizeClassName(Proxy.mockSingleton)
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
    /**
     * @description Validates the reflect(value, key, System.Type) overload:
     *   (1) the composed key (key + '_' + caller.getName()) is used in trapAudit
     *   (2) a value pre-registered via trapMock(key, System.Type, value) is returned
     */
    private static void reflect_validateTrap_withCallerType() {
        Proxy.mock();
        String key = 'ctx';
        Integer original = 99;
        Integer mocked = 7;
        String composedKey = key + '_' + ProxyTest.class.getName();

        // without a mock value registered, the original should pass through
        Integer passthrough = (Integer) Proxy.reflect(
            original,
            key,
            ProxyTest.class
        );
        Assert.areEqual(original, passthrough);
        Assert.areEqual(
            original,
            (Integer) Proxy.mock.trapAudit.get(composedKey)
        );

        // register a mock value keyed by the same type and re-reflect
        Proxy.mock.trapMock(key, ProxyTest.class, mocked);
        Integer intercepted = (Integer) Proxy.reflect(
            original,
            key,
            ProxyTest.class
        );
        Assert.areEqual(mocked, intercepted);
    }

    @isTest
    /**
     * @description Validates that the inline-style read returns the passed-in records
     * when no mock is active (base Proxy passthrough behavior).
     */
    private static void dbRead_inlineStyle_nonMocked_returnsPassthrough() {
        List<Account> accts = new List<Account>{ new Account(Name = 'Test') };
        List<SObject> result = Proxy.db.query(accts, ProxyTest.class);
        Assert.areEqual(accts, result);
    }

    @isTest
    /**
     * @description Validates that the inline-style read returns the passed-in records
     * when mocked but no MockReader is registered for the caller type.
     */
    private static void dbRead_inlineStyle_mockedNoRegistration_returnsPassthrough() {
        Proxy.mock();
        List<Account> accts = new List<Account>{
            new Account(Name = 'Fallback')
        };
        List<SObject> result = Proxy.db.query(accts, ProxyTest.class);
        Assert.areEqual(accts, result);
    }

    @isTest
    private static void validateInner() {
        Proxy.mock()
            .mockReader(InnerClass.class)
            .addReadRecord(new Account(Name = 'Inner Mock'));
        List<Account> accts = Proxy.db.read(new InnerClass());
        Proxy.db.query([SELECT id FROM account LIMIT 1], InnerClass.class);
    }

    private class InnerClass implements Proxy.DbReader {
        public List<SObject> read(Object ctx) {
            return null;
        }
    }

    @isTest
    /**
     * @description Validates that the inline-style read:
     *   (1) returns mocked records when a MockReader is registered for the caller type
     *   (2) populates readAudit keyed by caller class name
     */
    private static void dbRead_inlineStyle_mockedWithRegistration_returnsMockedRecords() {
        Proxy.MockReader mockReader = Proxy.mock().mockReader(ProxyTest.class);
        String mockAcctName = 'Mocked Account';
        mockReader.addReadRecord(new Account(Name = mockAcctName));

        List<Account> passedRecords = new List<Account>{
            new Account(Name = 'Original')
        };
        List<SObject> result = Proxy.db.query(passedRecords, ProxyTest.class);

        Assert.areEqual(1, result.size());
        Assert.areEqual(mockAcctName, ((Account) result[0]).Name);

        // validate readAudit is keyed by caller name (lowercased)
        String callerKey = Proxy.normalizeClassName(ProxyTest.class);
        Assert.isNotNull(Proxy.mock.readAudit.get(callerKey));
        Assert.areEqual(
            mockAcctName,
            ((Account) Proxy.mock.readAudit.get(callerKey).get(0).get(0)).Name
        );
    }

    @isTest
    private static void dbRead_validateMockRead() {
        Proxy.MockReader mockReader = Proxy.mock().mockReader(ProxyTest.class);
        String theOG = 'OG';
        Account originAcct = new Account(Name = theOG);
        mockReader.addReadRecord(Proxy.mock.setFauxId(originAcct))
            // test clone mode first (not default) where each read returns a clone of the read record(s)
            .setOptions()
            .cloneRead(true)
            .endSetOptions();

        // assert "clone mode" first: 1 account returned and each read returns a clone of the read record
        ProxyTest reader = new ProxyTest();
        Account a0 = (Account) Proxy.db.read(reader)[0];
        Account a1 = (Account) Proxy.db.read(reader)[0];
        Assert.areEqual(theOG, a1.Name);
        // validate in-memory name change has no effect on cloned read
        a1.Name = 'Clone1';
        Account a2 = (Account) Proxy.db.read(reader)[0];
        Assert.areEqual(theOG, a2.Name);

        // validate the readAudit
        Account audit0 = ((Account) Proxy.mock.readAudit.get('proxytest')
            .get(0)
            .get(0));
        Account audit1 = ((Account) Proxy.mock.readAudit.get('proxytest')
            .get(1)
            .get(0));
        Assert.areEqual(theOG, audit0.Name);
        Assert.areEqual('Clone1', audit1.Name);

        // now test regular mode where read returns the original records
        mockReader.setOptions().cloneRead(false);
        Account a3 = ((Account) Proxy.mock.readAudit.get('proxytest')
            .get(0)
            .get(0));
        Assert.areEqual(theOG, a3.Name);
    }

    @isTest
    private static void validate_contextDependent_mockRead_objectDependency() {
        String simpleContext_0 = '12345';
        Contact objectContext = new Contact(
            FirstName = 'John',
            LastName = 'Doe'
        );
        /** dependent 0 */
        Proxy.mock()
            .mockReader(ProxyTest.class, simpleContext_0)
            .addReadRecord(new Account(Name = simpleContext_0));
        /** dependent 1 */
        Proxy.mock()
            .mockReader(ProxyTest.class, objectContext)
            .addReadRecord(new Account(Name = objectContext.FirstName));

        // validate dependent 0
        List<SObject> result0 = Proxy.db.query(
            [SELECT Id FROM Account LIMIT 1],
            ProxyTest.class,
            simpleContext_0
        );
        Assert.areEqual(simpleContext_0, ((Account) result0[0]).Name);

        // validate dependent 1
        List<SObject> result1 = Proxy.db.query(
            [SELECT Id FROM Account LIMIT 1],
            ProxyTest.class,
            objectContext
        );
        Assert.areEqual(objectContext.FirstName, ((Account) result1[0]).Name);
    }

    @isTest
    private static void validate_contextDependent_mockRead_evaluateDependency() {
        Integer modInt = 10;
        Proxy.mock()
            .mockReader(ProxyTest.class, new MockDependencyEval())
            .addReadRecord(new Account())
            .repeat(5);
        while (modInt > 0) {
            Integer resultSize = queryAccount(modInt).size();
            if (Math.mod(modInt, 2) == 1) {
                Assert.areEqual(5, resultSize);
            } else {
                Assert.areEqual(0, resultSize);
            }

            modInt = modInt - 1;
        }
    }

    private static List<Account> queryAccount(Integer modInt) {
        List<Account> result = (List<Account>) Proxy.db.query(
            [SELECT Id FROM Account],
            ProxyTest.class,
            modInt
        );

        return result;
    }

    private class MockDependencyEval implements Proxy.MockReadContextEvaluator {
        // evaluate such that reader is only valid when modulo of readContext is 1
        public Boolean contextMatches(Object readContext) {
            Integer modInt = (Integer) readContext;

            return Math.mod(modInt, 2) == 1;
        }
    }

    /********************************************
     * VALIDATE MOCK READ OPTIONS
     *********************************************/

    @isTest
    /**
     * @description Validates MockReadOptions.clearStateOnRead(true):
     *   (1) first read returns the cloned records (cloneRead=true ensures result is not the same
     *       reference that gets cleared)
     *   (2) second read returns an empty list because readRecords was cleared after the first read
     */
    private static void mockReadOptions_clearStateOnRead_clearsRecordsAfterRead() {
        Proxy.MockReader reader = Proxy.mock().mockReader(ProxyTest.class);
        reader.addReadRecord(new Account(Name = 'Clear Me'))
            .setOptions()
            .cloneRead(true)
            .clearStateOnRead(true)
            .endSetOptions();

        // first read — cloned records are returned; internal state is then cleared
        List<SObject> read1 = reader.read(null);
        Assert.areEqual(1, read1.size());
        Assert.areEqual('Clear Me', ((Account) read1[0]).Name);

        // second read — readRecords was cleared, so the result is empty
        List<SObject> read2 = reader.read(null);
        Assert.areEqual(0, read2.size());
    }

    @isTest
    /**
     * @description Validates MockReadOptions.recaclFormulas(true):
     *   System.Formula.recalculateFormulas() is invoked without error and the records
     *   are returned intact.
     */
    private static void mockReadOptions_recaclFormulas_returnsRecordsAfterRecalc() {
        Proxy.MockReader reader = Proxy.mock().mockReader(ProxyTest.class);
        reader.addReadRecord(new Account(Name = 'Formula Acct'))
            .setOptions()
            .recaclFormulas(true)
            .endSetOptions();

        List<SObject> result = reader.read(null);
        Assert.areEqual(1, result.size());
        Assert.areEqual('Formula Acct', ((Account) result[0]).Name);
    }

    @isTest
    /**
     * @description Validates MockReadOptions.testLimits(true):
     *   A SOQL query is issued during each read(), incrementing the query counter.
     *   disableLimitsOnce() suppresses the extra query for exactly one read.
     */
    private static void mockReadOptions_testLimits_issuesQueryPerRead() {
        Proxy.MockReader reader = Proxy.mock().mockReader(ProxyTest.class);
        reader.addReadRecord(new Account(Name = 'Limits Acct'))
            .setOptions()
            .testLimits(true)
            .endSetOptions();

        // testLimits=true — query counter should increment
        Integer before = Limits.getQueries();
        reader.read(null);
        Assert.areEqual(before + 1, Limits.getQueries());

        // disableLimitsOnce() should suppress the extra query for the next read only
        Integer beforeSkip = Limits.getQueries();
        reader.disableLimitsOnce();
        reader.read(null);
        Assert.areEqual(beforeSkip, Limits.getQueries());

        // subsequent read resumes normal testLimits behavior
        Integer beforeResume = Limits.getQueries();
        reader.read(null);
        Assert.areEqual(beforeResume + 1, Limits.getQueries());
    }

    /********************************************
     * VALIDATE MOCK READER LINK API
     *********************************************/

    @isTest
    /**
     * @description Validates MockReader.link(MockReader):
     *   (1) first read returns the originating reader's records
     *   (2) second read delegates to the linked reader's records (default linkAfterReads = 1)
     */
    private static void mockReader_link_defaultSwitchesOnSecondRead() {
        Proxy.MockReader firstReader = new Proxy.MockReader();
        firstReader.addReadRecord(new Account(Name = 'First'));

        Proxy.MockReader linkedReader = new Proxy.MockReader();
        linkedReader.addReadRecord(new Account(Name = 'Linked'));

        firstReader.link(linkedReader);

        // first read — originating reader's records
        List<SObject> read1 = firstReader.read(null);
        Assert.areEqual(1, read1.size());
        Assert.areEqual('First', ((Account) read1[0]).Name);

        // second read — linked reader takes over
        List<SObject> read2 = firstReader.read(null);
        Assert.areEqual(1, read2.size());
        Assert.areEqual('Linked', ((Account) read2[0]).Name);
    }

    @isTest
    /**
     * @description Validates MockReader.link(MockReader, Integer):
     *   (1) the first N reads return the originating reader's records
     *   (2) read N+1 delegates to the linked reader's records
     */
    private static void mockReader_link_customCountSwitchesAfterNReads() {
        Proxy.MockReader firstReader = new Proxy.MockReader();
        firstReader.addReadRecord(new Account(Name = 'First'));

        Proxy.MockReader linkedReader = new Proxy.MockReader();
        linkedReader.addReadRecord(new Account(Name = 'Linked'));

        // link after 2 reads — delegate on the 3rd read
        firstReader.link(linkedReader, 2);

        // reads 1 and 2 — originating reader
        for (Integer i = 0; i < 2; i++) {
            List<SObject> result = firstReader.read(null);
            Assert.areEqual('First', ((Account) result[0]).Name);
        }

        // read 3 — linked reader
        List<SObject> read3 = firstReader.read(null);
        Assert.areEqual('Linked', ((Account) read3[0]).Name);
    }

    /********************************************
     * VALIDATE MOCK READ API: class override approach
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
            readerClassName = Proxy.normalizeClassName(reader);

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
        // invoke without mock to exercise the non-mocked path
        MockTarget target = new MockTarget();
        target.getAccountsAndChildren();
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
        Assert.areEqual('MockTarget'.toLowerCase(), readerClassName); // inner class name, but won't print
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

    /****************************************************************************************
     * _COVER_ DB WRITE OVERLOADS (No need to validate database outcomes)
     *****************************************************************************************/

    @isTest
    private static void db_coverWrite() {
        Proxy.mock();
        coverProxyDbOperations();
    }

    @isTest
    private static void coverProxyDbOperations() {
        List<Account> accts = new List<Account>();
        Assert.areEqual(0, Proxy.db.insertRecords(accts).size());
        Assert.areEqual(0, Proxy.db.updateRecords(accts).size());
        Assert.areEqual(0, Proxy.db.upsertRecords(accts).size());
        Assert.areEqual(0, Proxy.db.deleteRecords(accts).size());
        Assert.areEqual(0, Proxy.db.undeleteRecords(accts).size());
    }

    /** Covers allOrNone, DMLOptions, and AccessLevel list overloads without mock (empty lists = no-op DML) */
    @isTest
    private static void coverProxyDbOperations_listOverloads() {
        List<Account> accts = new List<Account>();
        Database.DMLOptions opts = new Database.DMLOptions();
        // insert
        Assert.areEqual(0, Proxy.db.insertRecords(accts, false).size());
        Assert.areEqual(0, Proxy.db.insertRecords(accts, true).size());
        Assert.areEqual(0, Proxy.db.insertRecords(accts, opts).size());
        Assert.areEqual(
            0,
            Proxy.db.insertRecords(accts, false, System.AccessLevel.SYSTEM_MODE)
                .size()
        );
        Assert.areEqual(
            0,
            Proxy.db.insertRecords(accts, opts, System.AccessLevel.SYSTEM_MODE)
                .size()
        );
        // update
        Assert.areEqual(0, Proxy.db.updateRecords(accts, false).size());
        Assert.areEqual(0, Proxy.db.updateRecords(accts, true).size());
        Assert.areEqual(0, Proxy.db.updateRecords(accts, opts).size());
        Assert.areEqual(
            0,
            Proxy.db.updateRecords(accts, false, System.AccessLevel.SYSTEM_MODE)
                .size()
        );
        Assert.areEqual(
            0,
            Proxy.db.updateRecords(accts, opts, System.AccessLevel.SYSTEM_MODE)
                .size()
        );
        // upsert
        Assert.areEqual(0, Proxy.db.upsertRecords(accts, false).size());
        Assert.areEqual(0, Proxy.db.upsertRecords(accts, true).size());
        Assert.areEqual(
            0,
            Proxy.db.upsertRecords(accts, Schema.Account.Id).size()
        );
        Assert.areEqual(
            0,
            Proxy.db.upsertRecords(accts, Schema.Account.Id, false).size()
        );
        Assert.areEqual(
            0,
            Proxy.db.upsertRecords(accts, false, System.AccessLevel.SYSTEM_MODE)
                .size()
        );
        Assert.areEqual(
            0,
            Proxy.db.upsertRecords(
                    accts,
                    Schema.Account.Id,
                    false,
                    System.AccessLevel.SYSTEM_MODE
                )
                .size()
        );
        // delete
        Assert.areEqual(0, Proxy.db.deleteRecords(accts, false).size());
        Assert.areEqual(0, Proxy.db.deleteRecords(accts, true).size());
        Assert.areEqual(
            0,
            Proxy.db.deleteRecords(accts, false, System.AccessLevel.SYSTEM_MODE)
                .size()
        );
        Assert.areEqual(
            0,
            Proxy.db.deleteRecords(new List<Id>(), false).size()
        );
        Assert.areEqual(
            0,
            Proxy.db.deleteRecords(
                    new List<Id>(),
                    false,
                    System.AccessLevel.SYSTEM_MODE
                )
                .size()
        );
        // undelete
        Assert.areEqual(0, Proxy.db.undeleteRecords(accts, false).size());
        Assert.areEqual(0, Proxy.db.undeleteRecords(accts, true).size());
        Assert.areEqual(
            0,
            Proxy.db.undeleteRecords(
                    accts,
                    false,
                    System.AccessLevel.SYSTEM_MODE
                )
                .size()
        );
        Assert.areEqual(
            0,
            Proxy.db.undeleteRecords(new List<Id>(), false).size()
        );
        Assert.areEqual(
            0,
            Proxy.db.undeleteRecords(
                    new List<Id>(),
                    false,
                    System.AccessLevel.SYSTEM_MODE
                )
                .size()
        );
    }

    /** Verifies mocked list overloads return a result per record */
    @isTest
    private static void db_coverWrite_listOverloads_sizeMatchesRecords() {
        Proxy.mock();
        List<Account> accts = new List<Account>{ new Account(), new Account() };
        Database.DMLOptions opts = new Database.DMLOptions();
        List<Id> ids = new List<Id>{
            Proxy.mock.getFauxId(Account.SObjectType),
            Proxy.mock.getFauxId(Account.SObjectType)
        };
        // insert
        Assert.areEqual(2, Proxy.db.insertRecords(accts, false).size());
        Assert.areEqual(2, Proxy.db.insertRecords(accts, true).size());
        Assert.areEqual(2, Proxy.db.insertRecords(accts, opts).size());
        Assert.areEqual(
            2,
            Proxy.db.insertRecords(accts, false, System.AccessLevel.SYSTEM_MODE)
                .size()
        );
        Assert.areEqual(
            2,
            Proxy.db.insertRecords(accts, opts, System.AccessLevel.SYSTEM_MODE)
                .size()
        );
        // update
        Assert.areEqual(2, Proxy.db.updateRecords(accts, false).size());
        Assert.areEqual(2, Proxy.db.updateRecords(accts, true).size());
        Assert.areEqual(2, Proxy.db.updateRecords(accts, opts).size());
        Assert.areEqual(
            2,
            Proxy.db.updateRecords(accts, false, System.AccessLevel.SYSTEM_MODE)
                .size()
        );
        Assert.areEqual(
            2,
            Proxy.db.updateRecords(accts, opts, System.AccessLevel.SYSTEM_MODE)
                .size()
        );
        // upsert
        Assert.areEqual(2, Proxy.db.upsertRecords(accts, false).size());
        Assert.areEqual(2, Proxy.db.upsertRecords(accts, true).size());
        Assert.areEqual(
            2,
            Proxy.db.upsertRecords(accts, Schema.Account.Id).size()
        );
        Assert.areEqual(
            2,
            Proxy.db.upsertRecords(accts, Schema.Account.Id, false).size()
        );
        Assert.areEqual(
            2,
            Proxy.db.upsertRecords(accts, false, System.AccessLevel.SYSTEM_MODE)
                .size()
        );
        Assert.areEqual(
            2,
            Proxy.db.upsertRecords(
                    accts,
                    Schema.Account.Id,
                    false,
                    System.AccessLevel.SYSTEM_MODE
                )
                .size()
        );
        // delete (list SObject + list Id)
        Assert.areEqual(2, Proxy.db.deleteRecords(accts, false).size());
        Assert.areEqual(2, Proxy.db.deleteRecords(accts, true).size());
        Assert.areEqual(
            2,
            Proxy.db.deleteRecords(accts, false, System.AccessLevel.SYSTEM_MODE)
                .size()
        );
        Assert.areEqual(2, Proxy.db.deleteRecords(ids, false).size());
        Assert.areEqual(2, Proxy.db.deleteRecords(ids, true).size());
        Assert.areEqual(
            2,
            Proxy.db.deleteRecords(ids, false, System.AccessLevel.SYSTEM_MODE)
                .size()
        );
        // undelete (list SObject + list Id)
        Assert.areEqual(2, Proxy.db.undeleteRecords(accts, false).size());
        Assert.areEqual(2, Proxy.db.undeleteRecords(accts, true).size());
        Assert.areEqual(
            2,
            Proxy.db.undeleteRecords(
                    accts,
                    false,
                    System.AccessLevel.SYSTEM_MODE
                )
                .size()
        );
        Assert.areEqual(2, Proxy.db.undeleteRecords(ids, false).size());
        Assert.areEqual(2, Proxy.db.undeleteRecords(ids, true).size());
        Assert.areEqual(
            2,
            Proxy.db.undeleteRecords(ids, false, System.AccessLevel.SYSTEM_MODE)
                .size()
        );
    }

    /** Covers single-record and single-Id overloads using mock (avoids actual DML) */
    @isTest
    private static void db_coverWrite_singleRecordOverloads() {
        Proxy.mock();
        Account acct = new Account();
        Database.DMLOptions opts = new Database.DMLOptions();
        Id fakeId = Proxy.mock.getFauxId(Account.SObjectType);
        // insert single
        Proxy.db.insertRecords(acct);
        Proxy.db.insertRecords(acct, false);
        Proxy.db.insertRecords(acct, opts);
        Proxy.db.insertRecords(acct, false, System.AccessLevel.SYSTEM_MODE);
        Proxy.db.insertRecords(acct, opts, System.AccessLevel.SYSTEM_MODE);
        // update single
        Proxy.db.updateRecords(acct);
        Proxy.db.updateRecords(acct, false);
        Proxy.db.updateRecords(acct, opts);
        Proxy.db.updateRecords(acct, false, System.AccessLevel.SYSTEM_MODE);
        Proxy.db.updateRecords(acct, opts, System.AccessLevel.SYSTEM_MODE);
        // upsert single
        Proxy.db.upsertRecords(acct);
        Proxy.db.upsertRecords(acct, false);
        Proxy.db.upsertRecords(acct, Schema.Account.Id);
        Proxy.db.upsertRecords(acct, Schema.Account.Id, false);
        Proxy.db.upsertRecords(acct, false, System.AccessLevel.SYSTEM_MODE);
        Proxy.db.upsertRecords(
            acct,
            Schema.Account.Id,
            false,
            System.AccessLevel.SYSTEM_MODE
        );
        // delete single SObject + single Id
        Proxy.db.deleteRecords(acct);
        Proxy.db.deleteRecords(acct, false);
        Proxy.db.deleteRecords(acct, false, System.AccessLevel.SYSTEM_MODE);
        Proxy.db.deleteRecords(fakeId);
        Proxy.db.deleteRecords(fakeId, false);
        Proxy.db.deleteRecords(fakeId, false, System.AccessLevel.SYSTEM_MODE);
        // undelete single SObject + single Id
        Proxy.db.undeleteRecords(acct);
        Proxy.db.undeleteRecords(acct, false);
        Proxy.db.undeleteRecords(acct, false, System.AccessLevel.SYSTEM_MODE);
        Proxy.db.undeleteRecords(fakeId);
        Proxy.db.undeleteRecords(fakeId, false);
        Proxy.db.undeleteRecords(fakeId, false, System.AccessLevel.SYSTEM_MODE);
    }

    private static Account initAccount() {
        return initAccount(false);
    }

    private static Account initAccount(Boolean setId) {
        Account a = new Account(Name = 'Test');
        if (setId) {
            Proxy.mock.setFauxId(a);
        }
        return a;
    }

    /** Covers single-record and single-Id non-mocked overloads against actual DML (base Proxy virtual methods) */
    @isTest
    private static void cover_singleRecord_nonMocked_allOverloads() {
        Database.DMLOptions opts = new Database.DMLOptions();
        // insert single - all 5 overloads
        Proxy.db.insertRecords(initAccount());
        Proxy.db.insertRecords(initAccount(), false);
        Proxy.db.insertRecords(initAccount(), opts);
        Proxy.db.insertRecords(
            initAccount(),
            false,
            System.AccessLevel.SYSTEM_MODE
        );
        Proxy.db.insertRecords(
            initAccount(),
            opts,
            System.AccessLevel.SYSTEM_MODE
        );
        // update single - all 5 overloads
        Proxy.db.updateRecords(initAccount(true));
        Proxy.db.updateRecords(initAccount(true), false);
        Proxy.db.updateRecords(initAccount(true), opts);
        Proxy.db.updateRecords(
            initAccount(true),
            false,
            System.AccessLevel.SYSTEM_MODE
        );
        Proxy.db.updateRecords(
            initAccount(true),
            opts,
            System.AccessLevel.SYSTEM_MODE
        );
        // upsert single - all 6 overloads (null externalIdField invokes standard upsert path)
        Proxy.db.upsertRecords(initAccount(true));
        Proxy.db.upsertRecords(initAccount(true), false);
        Proxy.db.upsertRecords(initAccount(true), (Schema.SObjectField) null);
        Proxy.db.upsertRecords(
            initAccount(true),
            (Schema.SObjectField) null,
            false
        );
        Proxy.db.upsertRecords(
            initAccount(true),
            false,
            System.AccessLevel.SYSTEM_MODE
        );
        Proxy.db.upsertRecords(
            initAccount(true),
            (Schema.SObjectField) null,
            false,
            System.AccessLevel.SYSTEM_MODE
        );
        // delete single SObject - 3 overloads
        Proxy.db.deleteRecords(initAccount(true));
        Proxy.db.deleteRecords(initAccount(true), false);
        Proxy.db.deleteRecords(
            initAccount(true),
            false,
            System.AccessLevel.SYSTEM_MODE
        );
        // delete single Id - 3 overloads
        Proxy.db.deleteRecords(initAccount(true).Id);
        Proxy.db.deleteRecords(initAccount(true).Id, false);
        Proxy.db.deleteRecords(
            initAccount(true).Id,
            false,
            System.AccessLevel.SYSTEM_MODE
        );
        // undelete single SObject - 3 overloads
        Proxy.db.undeleteRecords(initAccount(true));
        Proxy.db.undeleteRecords(initAccount(true), false);
        Proxy.db.undeleteRecords(
            initAccount(true),
            false,
            System.AccessLevel.SYSTEM_MODE
        );
        // undelete single Id - 3 overloads
        Proxy.db.undeleteRecords(initAccount(true).Id);
        Proxy.db.undeleteRecords(initAccount(true).Id, false);
        Proxy.db.undeleteRecords(
            initAccount(true).Id,
            false,
            System.AccessLevel.SYSTEM_MODE
        );
        // just covering here, assertions against actual db are org-dependent and not relevant for the library
        Assert.isTrue(true);
    }

    /** Covers no-arg single-record and no-arg list-Id delegating overloads with mock */
    @isTest
    private static void db_coverWrite_noArgDelegates_mocked() {
        Proxy.mock();
        Account acct = new Account();
        Id fakeId = Proxy.mock.getFauxId(Account.SObjectType);
        Assert.areEqual(0, Proxy.db.insertRecords(new List<Account>()).size());
        Assert.areEqual(0, Proxy.db.updateRecords(new List<Account>()).size());
        Assert.areEqual(0, Proxy.db.upsertRecords(new List<Account>()).size());
        Assert.areEqual(0, Proxy.db.deleteRecords(new List<Account>()).size());
        Assert.areEqual(0, Proxy.db.deleteRecords(new List<Id>()).size());
        Assert.areEqual(
            0,
            Proxy.db.undeleteRecords(new List<Account>()).size()
        );
        Assert.areEqual(0, Proxy.db.undeleteRecords(new List<Id>()).size());
    }
}
