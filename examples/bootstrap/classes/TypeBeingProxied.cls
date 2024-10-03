public inherited sharing class TypeBeingProxied {

    public static final String attrib = 'actual value';

    public static List<Account> getSomeRecords(){
        return new List<Account>{
            new Account(Name='TypeBeingProxied')
        };
    }

}