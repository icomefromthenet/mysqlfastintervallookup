#How to run these tests
These test are run using mysqlslap a client side testing tool.

``
sudo mysqlslap --user=ritree --password= -v --create-schema=ritree --query=/home/ritree/RITreeExample/src/tests/meets.mysql --iterations=100 --concurrency=300 
``

[Find innoDB index size.](http://dba.stackexchange.com/questions/1/what-are-the-main-differences-between-innodb-and-myisam/2194#2194) 
``mysql
SELECT FLOOR(SUM(data_length+index_length)/POWER(1024,2)) InnoDBSizeMB
FROM information_schema.tables WHERE engine='InnoDB';
``

[Recommended Setting for the size of the InnoDB Buffer Pool.](http://dba.stackexchange.com/questions/1/what-are-the-main-differences-between-innodb-and-myisam/2194#2194) 
``mysql
SELECT CONCAT(ROUND(KBS/POWER(1024,
IF(PowerOf1024<0,0,IF(PowerOf1024>3,0,PowerOf1024)))+0.49999),
SUBSTR(' KMG',IF(PowerOf1024<0,0,
IF(PowerOf1024>3,0,PowerOf1024))+1,1)) recommended_innodb_buffer_pool_size
FROM (SELECT SUM(data_length+index_length) KBS FROM information_schema.tables
WHERE engine='InnoDB') A,
(SELECT 2 PowerOf1024) B;
``

 Selectivity of index 
 
``mysql
-- Cardinality (number unique records) / Total number of records
SELECT round(((count(distinct node)/1000001) * 100),4) as selectivity
FROM `prices_adv` USE INDEX (`idx_prices_adv_upperLowerIndex`);
``

#@There are 2 version of every test

1. allens.mysql      - A query to test the allens relation .
2. allens_tree.mysql - A query that uses the RITree with same allens relation.

We hope the tree test execute with better results than basic allen versions.

