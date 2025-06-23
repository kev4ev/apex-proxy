/**
 * @description Provides base class for intercepting calls to Proxy singleton APIs (.db, .reflect())
 * for purposes of mocking.
 * Provided under the MIT License github.com/kev4ev/apex-proxy
 */

@isTest
public inherited sharing class TestProxy {
  private static Map<Schema.SObjectType, Integer> recordIdCounter = new Map<Schema.SObjectType, Integer>();

  /**********************
   * HELPER STATIC API
   ***********************/

  public static SObject setFauxId(SObject record) {
    record.Id = getFauxId(record);

    return record;
  }

  public static String getFauxId(SObject record) {
    Schema.SObjectType sot = record.getSObjectType();
    recordIdCounter.put(sot, (recordIdCounter.get(sot) ?? -1) + 1);
    String pos = recordIdCounter.get(sot).toString();

    String fauxId = String.format(
      '{0}{1}{2}',
      new List<String>{
        sot.getDescribe().getKeyPrefix(),
        pos,
        pos.length() < 12 ? '0'.repeat(12 - pos.length()) : ''
      }
    );

    return fauxId;
  }

  public abstract class Base extends Proxy {
    /******************************************************************
     * REFLECT API OVERRIDE - allows extending test class to implement
     ******************************************************************/
    public virtual override Object trap(Object value) {
      return value;
    }

    /******************************************************************
     * READER API OVERRIDE - REQUIRES extending class to implement
     ******************************************************************/

    public abstract override List<SObject> read(
      DbReader reader,
      Object readContext
    );

    /**************************************************
     * READER API - INTERNAL HELPER METHODS AND STATE
     *   - all helper methods can be chained
     **************************************************/
    private List<SObject> readRecords = new List<SObject>();
    private Map<Schema.SObjectType, List<Schema.ChildRelationship>> childrenRelMap = new Map<Schema.SObjectType, List<Schema.ChildRelationship>>();
    private Map<String, ChildRecords> childMap = new Map<String, ChildRecords>();
    private Boolean testLimits = false;

    /**
     * Add the root record for the next read() invocation
     * @param {SObject} record - the root record type to add
     * @returns {Base} for chaining
     **/
    protected Base addReadRecord(SObject record) {
      // set a faux id
      setFauxId(record);
      // conditionally add child meta
      Schema.SObjectType recordSobjectType = record.getSObjectType();
      if (!this.childrenRelMap.containsKey(recordSobjectType)) {
        this.childrenRelMap.put(
          recordSobjectType,
          recordSobjectType.getDescribe().getChildRelationships()
        );
      }
      // add the root
      this.readRecords.add(record);

      return this;
    }

    /**
     * Appends the current record to the read list the given number of times INCLUDING the current record.
     * @param {Integer} number of times to repeat the current record
     * @return {Base} this instance for chaining
     */
    protected Base repeat(Integer repeatCount) {
      return repeat(repeatCount, null, null);
    }

    /**
     * Appends the current record to the read list the given number of times INCLUDING the current record,
     * replacing the strings provided.
     * @param {Integer} repeatCount - number of times to repeat the current record
     * @param {Map<Schema.SObjectField, Object>} fieldMap - a map of fields to the values that will be written to them
     * @param {String} replacement - for String values in fieldMap, a string sequence to be replaced with the position of
     * the current item in the read list (i.e. Integer.toString())
     * @return {Base} this instance for chaining
     */
    protected Base repeat(
      Integer repeatCount,
      Map<Schema.SObjectField, String> fieldMap,
      String replacement
    ) {
      SObject curr = readRecords.get(readRecords.size() - 1);
      for (Integer pos = 0; pos < repeatCount; pos++) {
        // first iteration the target is curr itself so that repeat count is inclusive of the original
        SObject target = pos == 0 ? curr : curr.clone(false, true);
        if (fieldMap != null && fieldMap.size() > 0) {
          for (Schema.SObjectField field : fieldMap.keySet()) {
            replaceAndWrite(
              target,
              field,
              fieldMap.get(field),
              pos,
              replacement
            );
          }
        }
        if (pos > 0) {
          addReadRecord(target);
        }
      }

      return this;
    }

    private void replaceAndWrite(
      SObject record,
      Schema.SObjectField field,
      Object value,
      Integer position,
      String positionReplacement
    ) {
      if (String.isNotBlank(positionReplacement)) {
        try {
          value = ((String) value)
            .replaceAll(positionReplacement, position.toString());
        } catch (Exception e) {
          // not a String
        }
      }
      record.put(field, value);
    }

    protected Base relateChild(SObject child) {
      return relateChild(child, this.readRecords.size() - 1);
    }

    protected Base relateChild(SObject child, Integer rootRecordPosition) {
      // set faux id
      setFauxId(child);
      // find the relationship name
      SObject parent = this.readRecords.get(rootRecordPosition);
      Schema.SObjectType parentType = parent.getSObjectType();
      Schema.SObjectType childType = child.getSObjectType();
      String relationshipName;
      for (Schema.ChildRelationship rel : this.childrenRelMap.get(parentType)) {
        if (rel.getChildSObject() == childType) {
          relationshipName = rel.getRelationshipName();

          break;
        }
      }
      // throw if invalid relationship
      if (String.isBlank(relationshipName)) {
        throw new TestProxyException(
          childType.getDescribe().getName() +
            ' is not a valid child of ' +
            parentType.getDescribe().getName()
        );
      }

      // get or init ChildRecords by faux id of the parent
      String fauxParentId = this.readRecords.get(rootRecordPosition).Id;
      ChildRecords children = this.childMap.get(fauxParentId);
      if (children == null) {
        children = new ChildRecords();
        childMap.put(fauxParentId, children);
      }
      children.add(child);
      // delegate field set and return self
      setRootFieldDynamic(rootRecordPosition, relationshipName, children);

      return this;
    }

    protected Base relateParent(SObject parent, Schema.SObjectField field) {
      return relateParent(parent, field, this.readRecords.size() - 1);
    }

    protected Base relateParent(
      SObject parent,
      Schema.SObjectField field,
      Integer rootRecordPosition
    ) {
      // set faux id
      setFauxId(parent);
      // normalize relationship name
      String rawName = field.getDescribe().getName();
      String relName = rawName.endsWith('__c')
        ? rawName.replace('__c', '__r')
        : rawName.replace('Id', '');
      // delegate field set and return self
      setRootFieldDynamic(rootRecordPosition, relName, parent);

      return this;
    }

    private void setRootFieldDynamic(
      Integer rootRecordPosition,
      String fieldKey,
      Object fieldValue
    ) {
      // serialize and deserialize
      SObject root = this.readRecords.get(rootRecordPosition);
      Map<String, Object> rootMap = (Map<String, Object>) JSON.deserializeUntyped(
        JSON.serialize(root)
      );
      rootMap.put(fieldKey, fieldValue);
      // replace
      SObject newRoot = (SObject) JSON.deserialize(
        JSON.serialize(rootMap),
        SObject.class
      );
      // reset the record in the correct buildtime position
      this.readRecords[rootRecordPosition] = newRoot;
    }

    /**
     * When invoked, a minimal overhead query will be executed for each call to read() such
     * that limits testing can be simulated. Note that otal queries can be simulated but rows
     * retrieved cannot.
     */
    protected Base testLimits() {
      this.testLimits = true;

      return this;
    }

    protected List<SObject> read() {
      return read(true);
    }

    /**
     * @description Read the previously constructed SObject list
     * @param {Boolean} [resetState=true] when true (default) internal state will be cleared
     * @returns {List<SObject>}
     */
    protected List<SObject> read(Boolean resetState) {
      // conditionally mock limits
      if (this.testLimits == true) {
        Integer cnt = [SELECT COUNT() FROM Account LIMIT 1];
      }
      // create the list for return
      List<SObject> result = resetState
        ? this.readRecords.deepClone(true, true, true)
        : this.readRecords;
      // conditionaly reset internal state for subsequent mock
      if (resetState) {
        this.readRecords.clear();
        this.childMap.clear();
        this.testLimits = false;
      }

      return result;
    }

    /******************************************************************
     * WRITE API OVERRIDE - allows extending class to override
     ******************************************************************/

    /** @description overridable; default implementation returns an empty list matching the size of records */
    public virtual override List<Database.SaveResult> insertRecords(
      List<SObject> records
    ) {
      return new List<Database.SaveResult>(records.size());
    }

    /** @description overridable; default implementation returns an empty list matching the size of records */
    public virtual override List<Database.SaveResult> updateRecords(
      List<SObject> records
    ) {
      return new List<Database.SaveResult>(records.size());
    }

    /** @description overridable; default implementation returns an empty list matching the size of records */
    public virtual override List<Database.UpsertResult> upsertRecords(
      List<SObject> records
    ) {
      return new List<Database.UpsertResult>(records.size());
    }

    /** @description overridable; default implementation returns an empty list matching the size of records */
    public virtual override List<Database.DeleteResult> deleteRecords(
      List<SObject> records
    ) {
      return new List<Database.DeleteResult>(records.size());
    }

    /** @description overridable; default implementation returns an empty list matching the size of records */
    public virtual override List<Database.UndeleteResult> undeleteRecords(
      List<SObject> records
    ) {
      return new List<Database.UndeleteResult>(records.size());
    }
  }

  private class ChildRecords {
    public Integer totalSize = 0;
    public Boolean done = true;
    public List<SObject> records = new List<SObject>();
    /** @constructor */
    public ChildRecords() {
    }

    public void add(SObject child) {
      this.records.add(child);
      this.totalSize = this.records.size();
    }
  }

  private class TestProxyException extends Exception {
  }
}
