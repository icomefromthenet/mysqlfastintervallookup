RI Tree
===================================== 

The Relation Interval Tree is an adaption of and Interval Tree structure into
a relational context. The algorithm was outlined out in a paper called [Managing Intervals Efficiently in Object-Relational Databases](http://www.dbs.ifi.lmu.de/Publikationen/Papers/VLDB2000.pdf).

I have implement their fixed height tree to speed up my intersection queries.

Part A - The Fork Node
--------------------------------------

The RI Tree uses a virtual heirarchy that is stored with each interval and know as the fork node.
Foreach update and insert the value of the fork node must be calculated. 

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
As I mentioned earlier I impelement a fixed height tree, using the max size of the slots table. As this table is built during the install I know the size will
remain fixed. I use a query to fetch the size, as I vary the number of calendar years that the table contains during testing.

Key points to take away from forkNode. 

1. Root is always set to max tree height, highe the tree the more recursion will occur in the loop.
2. Use bisection to iteratre of the tree (divide by 2). 
3. This does not use and I/O.
4. If we change the hight of the tree we need to change every forkNode.


Part B - The Schema and indexes
--------------------------------------

To the base table we need to add the following:

```mysql
  
  -- Value of the fork node, used to part of the RI Tree
  `node` INT NOT NULL,
  
  -- RI Indexes
  INDEX `idx_timeslot_slots_tree_ri_lower` (`timeslot_id`,`node`,`opening_slot_id`),
  INDEX `idx_timeslot_slots_tree_ri_upper` (`timeslot_id`,`node`,`closing_slot_id`),

```

We need a column to store the forkNode and indexes that speed up the searches.

If this table did not use a second form of grouping we would only use indexes like

```mysql
    -- RI Indexes
  INDEX `idx_timeslot_slots_tree_ri_lower` (`node`,`opening_slot_id`),
  INDEX `idx_timeslot_slots_tree_ri_upper` (`node`,`closing_slot_id`),
```

As this table is split into timeslot groups and my queries are only interested in
timeslots that are part of the same group. The `timeslot_id` must be added as the first
index. 

Our later query will use the firts two `timeslot_id` and `node` as partial index if the `opening_slot_id` precedes our group the index could not be used and this would slow the query down. 
Always add extra groups to the left for RI Tree specific indexes.


Part C - Left and right nodes
--------------------------------------
To query an intersection we need three result sets, The values on the left the values on the right and the values in between.

These functions use integer math to find Nodes that are either on the left or right by traversing the tree in memory.
As the tree is fixed height we have the root and can avoid I/O while traversing.

However when a node is found it needs to be recorded and as MYSQL can not return a result to a query the values need to be stored in a temp table. 

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
2. Use fixed root and bisection to traverse the tree. If the height changed we need to ensure these procedures know.
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

I had to specify the indexes as the optimizer could not produce a stable plan for first query.
An index is used for each query making the overall result must faster than normal interval query
that requires a full table scan. 


Parts E - Observation
--------------------------------------
Using the tests in [basic.mysql](basic.mysql) and [normal.mysql](normal.mysql) as a comparision to normal interval query I found that I was able to achieve a large reduction in query time.

Duration(sec):
Normal       : 0.07690900
RITree       : 0.00163325


