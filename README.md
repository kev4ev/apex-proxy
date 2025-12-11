# Apex Proxy

Apex unit tests - they're a fact of life for Salesforce developers. But have you been writing them wrong all this time?

If your unit tests are writing and reading from the database, chances are what you're really writing are _integration tests_. The proxy pattern allows you to optimize your unit tests for performance, stability, and isolation.

## Installation

To use this library in your orgs simply clone this repo to your local machine and copy the classes from [./lib/classes](./lib/classes/) into your sf project directory. **Note:** before deploying ensure that the class names do not conflict with any existing in the target org.

<!-- TODO npx -->

## Usage

### Functional Code

### Unit Tests

## Known Issues

<!-- TODO open issues -->

### Calling `repeat()` after `relateParent()` or `relateChild()`

When calling `repeat()` after relating parent and/or child records to a root record, the kin records will have identical Ids, causing probable exceptions if they are used in a `Set` or as `Map` keys.

**Possible fix.** Use wrapper classes for SObjects instead of SObjects directly. Would be a larger rewrite but would also improve performance by reducing (eliminating?) need for JSON serialization / parsing.

## Contributing

<!-- TODO -->
