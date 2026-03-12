# Apex Proxy

Apex unit tests - they're a fact of life for Salesforce developers. But have you been writing them wrong all this time?

If your unit tests are writing and reading from the database, chances are what you're really writing are _integration tests_. The proxy pattern allows you to optimize your unit tests for performance, stability, and isolation.

## Installation

From the root of your Salesforce DX project (the directory containing `sfdx-project.json`), run:

```bash
npx @machso/apexproxy init
```

This will copy `Proxy.cls` and `ProxyTest.cls` (and their metadata files) into the `main/default/classes` subdirectory of your project's default package directory. Before deploying, ensure the class names do not conflict with existing classes in your target org.

## Usage

### Functional Code

Route all database interactions through the `Proxy` APIs in your production code. This allows unit tests to intercept and stub those calls without any changes to your business logic.

#### Read Styles

There are two ways to route SOQL reads through the proxy. Choose the one that best fits your codebase.

---

**Inline style** — keep the query where it is, pass the results and the calling class through the proxy. Best for greenfield code or quick adoption since no interface implementation is required.

```java
public class AccountService {
    public List<Account> getAccounts(String filter) {
        // Pass results AND this class's type so tests can intercept by caller
        return Proxy.db.read(
            [SELECT Id, Name FROM Account WHERE Name LIKE :filter],
            AccountService.class
            filter /** optionally pass read context */
        );
    }
}
```

In production the proxy is a transparent pass-through — `results` is returned unchanged and the second and (optional) third arguments are ignored. In tests, any `MockReader` registered for `AccountService` takes over (see [unit tests](#unit-tests) below).

---

**Implementation style** — move the query into a dedicated class that implements `Proxy.DbReader`. Best for orgs where an existing framework or selector pattern (e.g. FFLIB) is established or when you want to reuse a reader across multiple classes.

```java
public class AccountReader implements Proxy.DbReader {
    public List<SObject> read(Object ctx) {
        String filter = (String) ctx;
        return [SELECT Id, Name, (SELECT Id, LastName FROM Contacts)
                FROM Account WHERE Name LIKE :filter];
    }
}

public class AccountService {
    public List<Account> getAccounts(String filter) {
        // Route reads through Proxy.db so tests can intercept them
        return (List<Account>) Proxy.db.read(new AccountReader(), filter);
    }

    public void saveAccounts(List<Account> accounts) {
        // Route writes through Proxy.db so tests can intercept them
        Proxy.db.insertRecords(accounts);
    }
}
```

Read on in [unit tests](#unit-tests) below to see how easily you can now stub query results during test execution.

**Use `Proxy.reflect()` to trap value assignment in setters or variables.** This is only necessary if you wish to mock the value set during unit testing.

```java
public class MyClass {
    public String status {
        get;
        set { status = (String) Proxy.reflect(value, 'status'); }
    }
}
```

During normal runtime `Proxy.reflect()` is a pass-through — it returns the value unchanged. In tests you can intercept and replace the value (see below).

**Available DB write methods** (all route through the singleton proxy):

```java
Proxy.db.insertRecords(records);
Proxy.db.updateRecords(records);
Proxy.db.upsertRecords(records);
Proxy.db.deleteRecords(records);
Proxy.db.undeleteRecords(records);
```

### Unit Tests

Call `Proxy.mock()` at the start of each test to activate mock mode. In mock mode:

- All `Proxy.db` write operations return empty result lists of the correct type — no database activity occurs.
- `Proxy.db.read()` returns whatever you configure via `mockReader()`.
- `Proxy.reflect()` returns the original value unless you stub it with `trapMock()`.

> **Heads up — reader lookup uses the innermost class name only.**
> When you call `Proxy.mock().mockReader(SomeClass.class)`, the proxy registers the mock under the _innermost_ class name, lowercased. Namespaces and outer class qualifiers are stripped. So `MyNamespace.OuterClass.AccountReader` is looked up as `accountreader`, the same key as a top-level `AccountReader`.
>
> This applies to BOTH the inline and implementation read styles:
>
> Therefore be mindful of **naming conflicts within a given unit test**. For example, if you're mocking both a top-level class, `AccountReader`, and an inner class `ContactSelector.AccountReader` **these will generate a naming conflict during testing.**
>
> The best way to avoid this conflict by splitting your unit test logic into multiple tests but, where not feasible, there are other approaches such as utilizing a single MockReader for overlapping mocks and returning results based on the readContext (assuming it is passed).

**Stubbing a SOQL read:**

```java
@isTest
private static void testGetAccounts() {
    // Activate mock mode and configure a mock reader for AccountReader
    Proxy.MockReader mocker = Proxy.mock().mockReader(AccountReader.class);
    mocker.addReadRecord(new Account(Name = 'Acme'))
          .addReadRecord(new Account(Name = 'Globex'));

    // Exercise production code — no DB queries execute
    List<Account> results = new AccountService().getAccounts('A%');
    Assert.areEqual(2, results.size());
    Assert.areEqual('Acme', results[0].Name);
}
```

**Stubbing reads with related records:**

```java
@isTest
private static void testGetAccountsWithRelations() {
    Proxy.MockReader mocker = Proxy.mock().mockReader(AccountReader.class);

    // Build a root Account with a parent Account and two child Contacts
    mocker.addReadRecord(new Account(Name = 'Acme'))
          .relateParent(new Account(Name = 'Parent Corp'), Schema.Account.ParentId)
          .relateChild(new Contact(LastName = 'Smith'))
          .relateChild(new Contact(LastName = 'Jones'));

    List<Account> results = new AccountService().getAccounts('%');
    Account a = results[0];
    Assert.areEqual('Parent Corp', a.Parent.Name);
    Assert.areEqual(2, a.Contacts.size());
}
```

**Asserting trapped reflection values:**

```java
@isTest
private static void testStatusSetter() {
    Proxy.mock();  // activates mock; reflect() now records values in trapAudit

    MyClass obj = new MyClass();
    obj.status = 'active';

    // Verify the value that was passed through reflect()
    Assert.areEqual('active', Proxy.mock.trapAudit.get('status'));
}
```

**Intercepting reads and writes with a custom Mock subclass:**

For advanced scenarios you can extend `Proxy.Mock` to fully control read and write behavior:

```java
private class MyMock extends Proxy.Mock {
    public override List<SObject> read(Proxy.DbReader reader, Object ctx) {
        // return any records you want regardless of which reader was passed
        return new List<SObject>{ new Account(Name = 'Stubbed') };
    }

    public override List<Database.SaveResult> insertRecords(List<SObject> records) {
        // custom insert behavior (e.g. throw, or inspect records)
        return new List<Database.SaveResult>(records.size());
    }
}

@isTest
private static void testWithCustomMock() {
    Proxy.mock(new MyMock());
    List<Account> results = new AccountService().getAccounts('%');
    Assert.areEqual('Stubbed', results[0].Name);
}
```

## Known Issues

<!-- TODO open issues -->

### Calling `repeat()` after `relateParent()` or `relateChild()`

When calling `repeat()` after relating parent and/or child records to a root record, the kin records will have identical Ids, causing probable exceptions if they are used in a `Set` or as `Map` keys.

**Possible fix.** Use wrapper classes for SObjects instead of SObjects directly. Would be a larger rewrite but would also improve performance by reducing (eliminating?) need for JSON serialization / parsing.

## Contributing

Contributions are welcome! Please follow this process:

1. **Open an issue** first to discuss the bug, feature, or improvement you have in mind. This allows maintainers to provide feedback before you invest time writing code.
2. **Fork** the repository and create a branch from `main` for your changes.
3. **Make your changes.** If adding or fixing behavior, include or update `ProxyTest.cls` to cover it.
4. **Open a pull request** against the `main` branch of this repository. Reference the issue number in the PR description (e.g. `Closes #42`).

Please keep PRs focused — one issue per PR makes review easier.
