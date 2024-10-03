@isTest
private inherited sharing class BootstrapBill_Test {

    private static final String PROXY_ATTRIB = 'ProxyString';
    private static final List<Account> PROXY_ACCTS = new List<Account>{
        new Account(Name='ProxyAccount')
    };

    @isTest
    private static void validateProxiedAttrib(){
        BootstrapBill bb = new BootstrapBill();
        bb.accessor = new Proxy();
        Assert.areEqual(PROXY_ATTRIB, bb.getDependencyAttrib());
        Assert.areEqual(PROXY_ACCTS[0].Name, bb.getDependencyAccounts()[0].Name);
    }

    private class Proxy implements Proxy.Proxies.TypeAccessor{

        public Object call(String accessorPath){
            switch on accessorPath {
                when 'attrib' {
                    return PROXY_ATTRIB;
                }
                when 'getSomeRecords' {
                    return PROXY_ACCTS;
                }
                when else {
                    return null;
                }
            }
        }

        public Object call(String accessorPath, List<Object> args){
            return null;
        }
    }

}