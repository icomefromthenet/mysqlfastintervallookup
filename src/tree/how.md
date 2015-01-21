RI Tree
===================================== 

The Relation Interval Tree is an adaption of and Interval Tree structure into
a relational context. The algorithm was outlined out in a paper called [Managing Intervals Efficiently in Object-Relational Databases](http://www.dbs.ifi.lmu.de/Publikationen/Papers/VLDB2000.pdf).

I have implement their fixed height tree to speed up my intersection queries.

Part A - The Fork Node
--------------------------------------

The RI Tree uses a virtual heirarchy that is stored along with each interval and is know as the fork node.
For every update and insert the fork node must be calculated and included. 

I impelement the following function to calculate the fork node.

```mysql
CREATE FUNCTION `utl_fork_node`(lower INT, upper INT) RETURNS INTEGER 
BEGIN
	-- Used in the RI Tree 
	DECLARE treeHeight INT DEFAULT 0;
	DECLARE treeRoot INT DEFAULT 0; 
	DECLARE treeNode INT DEFAULT 0; 
	DECLARE searchStep INT DEFAULT 0;
	
	SET treeHeight  = ceil(LOG2((SELECT MAX(slot_id) FROM slots)+1));
	SET treeRoot    = power(2,(treeHeight-1)); 
	SET treeNode    = treeRoot;
	SET searchStep  =  treeNode / 2;

	myloop:WHILE searchStep >= 1 DO
	    
	    IF upper < treeNode THEN SET treeNode = treeNode - searchStep;
	    ELSEIF lower > treeNode THEN SET treeNode = treeNode + searchStep;
	    ELSE LEAVE myloop;
	    END IF;
	    
	    SET searchStep = searchStep / 2;
	    
  	END WHILE myloop;
	
	RETURN treeNode;
	
END;
$$
```
I am using the max slot_id of the slots table as my root node and as this table is built during the install I know the size will
remain fixed. In the function I used a query to fetch the max value as I vary the number of calendar years that are genereted during the install while running tests.

Key points to take away from forkNode. 

1. Root is always set to max tree height and the higher the tree the greater the number of loop iterations.
2. Use bisection to iteratre of the tree (divide by 2). 
3. This does not use any disk I/O but recursion does chew cpu cycles.
4. If we change the height of the tree we need to update every forkNode on the table.


Part B - The Schema and indexes
--------------------------------------

We need a column to store the forkNode and indexes that speed up the searches.

To the base table we need to add the following:

```mysql
  
  -- Value of the fork node, used to part of the RI Tree
  `node` INT NOT NULL,
  
  -- RI Indexes
  INDEX `idx_timeslot_slots_tree_ri_lower` (`timeslot_id`,`node`,`opening_slot_id`),
  INDEX `idx_timeslot_slots_tree_ri_upper` (`timeslot_id`,`node`,`closing_slot_id`),

```


If this table did not use a second form of grouping we would only use indexes like:

```mysql
    -- RI Indexes
  INDEX `idx_timeslot_slots_tree_ri_lower` (`node`,`opening_slot_id`),
  INDEX `idx_timeslot_slots_tree_ri_upper` (`node`,`closing_slot_id`),
```

As this table is split into timeslot groups and my queries are only interested in
timeslots that are part of the same group the `timeslot_id` must be added as the first
index. 

Our later query will use the first two columns `timeslot_id` and `node` as partial index but if the `opening_slot_id` precedes our group column the query optimizer will not use our index. It is important to add extra group columns to the left on the RI Tree indexes.


Part C - Left and right nodes
--------------------------------------
To query an intersection we need three result sets the first set is the values on the left of forkNode the second is values on the right of the forkNode and the last set is the forkNodes between the upper and lower bounds of the interval.

These procedures use a loop to decent the tree heirarchy to find forkNodes that are either on the left or right avoiding I/O while traversing.
However when a node is found it needs to be recorded and since MYSQL procedures can not return result sets the values are stored in a temp table and as the table is using the memory engine, we avoid disk I/O.  

```mysql

CREATE PROCEDURE `bm_rules_timeslot_left_nodes`(lower INT, upper INT)
BEGIN

  DECLARE treeHeight INT DEFAULT 0;
	DECLARE treeRoot INT DEFAULT 0; 
	DECLARE treeNode INT DEFAULT 0; 
	DECLARE searchStep INT DEFAULT 0;
	
	SET treeHeight  = ceil(LOG2((SELECT MAX(`slot_id`) FROM `slots`)+1));
	SET treeRoot    = power(2,(treeHeight-1)); 
	SET treeNode    = treeRoot;
	SET searchStep  =  treeNode / 2;

    -- holds a colletion of forkNodes 
   	DROP TEMPORARY TABLE IF EXISTS `timeslot_left_nodes_result`;
    CREATE TEMPORARY TABLE `timeslot_left_nodes_result` (`node` INT NOT NULL PRIMARY KEY)ENGINE=MEMORY; 
    
    
   -- descend from root node to lower
   myloop:WHILE searchStep >= 1 DO
  
    -- right node
    IF lower < treeNode THEN
      SET treeNode = treeNode - searchStep;
  
    -- left node
    ELSEIF lower > treeNode THEN
  
      INSERT INTO `timeslot_left_nodes_result`(node) VALUES(treeNode);
      SET treeNode = treeNode + searchStep;
  
    -- lower
    ELSE LEAVE myloop;
    END IF;  

    SET searchStep = searchStep / 2;
  
  END WHILE myloop;

END;
$$


DROP PROCEDURE IF EXISTS `bm_rules_timeslot_right_nodes`$$

CREATE PROCEDURE `bm_rules_timeslot_right_nodes`(lower INT, upper INT)
BEGIN

  DECLARE treeHeight INT DEFAULT 0;
	DECLARE treeRoot INT DEFAULT 0; 
	DECLARE treeNode INT DEFAULT 0; 
	DECLARE searchStep INT DEFAULT 0;
	
	SET treeHeight  = ceil(LOG2((SELECT MAX(`slot_id`) FROM `slots`)+1));
	SET treeRoot    = power(2,(treeHeight-1)); 
	SET treeNode    = treeRoot;
	SET searchStep  =  treeNode / 2;

    -- holds a colletion of forkNodes 
   	DROP TEMPORARY TABLE IF EXISTS `timeslot_right_nodes_result`;
    CREATE TEMPORARY TABLE `timeslot_right_nodes_result` (`node` INT NOT NULL PRIMARY KEY)ENGINE=MEMORY; 
    
    
   -- descend from root node to lower
   myloop:WHILE searchStep >= 1 DO
  
    -- right node
    IF upper > treeNode THEN
      SET treeNode = treeNode + searchStep;
  
    -- left node
    ELSEIF upper < treeNode THEN
  
      INSERT INTO `timeslot_right_nodes_result`(node) VALUES(treeNode);
      SET treeNode = treeNode - searchStep;
  
    -- lower
    ELSE LEAVE myloop;
    END IF;  

    SET searchStep = searchStep / 2;
  
  END WHILE myloop;

END;
$$

```

Key points to take away.

1. The procedures do not require I/O to traverse the tree and using memory temp tables stops disk I/O when storing the result.
2. Uses fixed root and bisection to traverse the tree.
3. These temp tables are globals.


Parts D - Basic Query
--------------------------------------

We have three parts to intersections query

1. Call the right and left nodes procedures to ensure the tmp tables are populated.
2. Execute three select queries and combine the results.

```mysql

    CALL bm_rules_timeslot_left_nodes(@minslot,@maxslot);
    CALL bm_rules_timeslot_right_nodes(@minslot,@maxslot);



    SELECT i.*
    FROM timeslot_slots_tree i USE INDEX (`idx_timeslot_slots_tree_ri_upper`)
    JOIN timeslot_left_nodes_result l ON i.node = l.node
    AND i.timeslot_id = 1
    -- As where using closed-open interval format we only use '>' as given two intervals p and q that p2 = q1
    -- if we used '>=' operator we would match nodes that qualify as 'meet' allens relation which we don't want.
    AND i.closing_slot_id > @minslot
    UNION ALL
    SELECT i.*
    FROM timeslot_slots_tree i USE INDEX (`idx_timeslot_slots_tree_ri_lower`)
    JOIN timeslot_right_nodes_result l ON i.node = l.node
    AND i.timeslot_id = 1
    AND i.opening_slot_id <= @maxslot
    UNION ALL 
    SELECT i.*
    FROM timeslot_slots_tree i
    WHERE node BETWEEN @minslot AND @maxslot
    AND i.timeslot_id = 1;
    

```

As the optimizer could not produce a stable execution plan I had to specify the indexes to be used but it is these index that make the overall result faster so it is important that they are used in the correct order. 


Parts E - Observation
--------------------------------------
Using the tests in [basic.mysql](basic.mysql) and [normal.mysql](normal.mysql) as a comparision interval query I found that I was able to achieve a large reduction in query time.

Duration(sec):
Normal       : 0.07690900
RITree       : 0.00163325


