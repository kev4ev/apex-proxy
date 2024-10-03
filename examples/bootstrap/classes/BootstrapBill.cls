public inherited sharing class BootstrapBill implements Proxy.Proxies.TypeAccessor {

    public enum DEPS { attrib, getSomeRecords }

    @testVisible
    private Proxy.Proxies.TypeAccessor accessor = this;

    public Object call(String accessorPath){
        switch on accessorPath {
            when 'attrib' {
                return TypeBeingProxied.attrib;
            }
            when 'getSomeRecords' {
                return TypeBeingProxied.getSomeRecords();
            }
            when else{ return null; }
        }
    }

    public Object call(String accessorPath, List<Object> args){
        // not used here
        return null;
    }

    public String getDependencyAttrib(){
        return (String) accessor.call('attrib');
    }

    public List<Account> getDependencyAccounts(){
        return (List<Account>) accessor.call('getSomeRecords');
    }

}