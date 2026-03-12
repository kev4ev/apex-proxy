# Claude requirements

I want to make this repo a published npm package. Please help me implement the following:

1. the only published files should be `force-app/main/default/classes`, `README.md`, and `package.json`
2. the package must be `npx`-invocable as described in step 3
3. when a user runs `npx @machso/apexproxy init` a script will execute that reads the cwd in search of an `sfdx-project.json` file.
   3a. if the file is found: - read the property path `.packageDirectories` and find the object where `.default` is `true`; if no match is found proceed to step 3b - if the default directory is `force-app` append `/default/main` to its path - copy the classes from package directory `force-app/main/default/classes` to the user's default directory
   3b. if the file is NOT found, write an error to stdout that the file must be present and include a default package directory path
4. Read and understand the `Proxy.cls` and `ProxyTest.cls` classes in `force-app/main/default` and update the `README.md` file's "installation" and "usage" section. In the latter highlight how the library can be used to intercept calls to the database, during normal runtime, and stub calls to the database when running unit tests. Provide example code.
