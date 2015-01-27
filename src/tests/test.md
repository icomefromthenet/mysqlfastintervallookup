#How to run these tests
These test are run using mysqlslap a client side testing tool.

``
sudo mysqlslap --user=ritree --password= -v --create-schema=ritree --query=/home/ritree/RITreeExample/src/tests/meets.mysql --iterations=100 --concurrency=300 
``

#@There are 2 version of every test

1. allens.mysql      - A query to test the allens relation .
2. allens_tree.mysql - A query that uses the RITree with same allens relation.

We hope the tree test execute with better results than basic allen versions.

