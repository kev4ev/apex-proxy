@isTest
public inherited sharing class DataReaderTestStub implements DataInterfaces.Reader {
    Schema.SObjectType sobjecttype;
    public DataReaderTestStub(Schema.SObjectType sobjecttype) {
        this.sobjecttype = sobjecttype;
    }

    public Schema.SObjectType handlesType() {
        return this.sobjecttype;
    }

    public List<SObject> read() {
        return null;
    }

    public String stubValidator(String validationArg) {
        return validationArg;
    }
}
