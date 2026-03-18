public class AccountService {
    public static void handleReassignment(Id accountId) {
        // mock the READ by wrapping your SOQL statement - this has ZERO runtime effects outside unit tests
        Account acct = [
            SELECT
                Id,
                Rating,
                OwnerId,
                Owner.UserRole.DeveloperName,
                NumberOfEmployees,
                (SELECT Id, OwnerId FROM Contacts),
                (SELECT Id, OwnerId FROM Cases)
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];

        for (Contact c : acct.contacts) {
            c.OwnerId = acct.OwnerId;
        }
        // mock the WRITE operations - again zero effect outside unit tests
        update acct.contacts;

        for (Case c : acct.cases) {
            c.OwnerId = acct.OwnerId;
        }
        // ditto
        update acct.cases;

        // read on...
        setAccountRating(acct);

        update acct;
    }

    private static void setAccountRating(Account acct) {
        // logic here...
    }
}
