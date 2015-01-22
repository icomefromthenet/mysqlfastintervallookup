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
I am using the max slot_id of the slots table to determine the height of my tree and as this table is built during the install I know the size will
remain fixed. 

```mysql
SET treeHeight  = ceil(LOG2((SELECT MAX(slot_id) FROM slots)+1));
```

After generating slots for 10 calender ears the result of line above produces a height of 24 If you are unsure of the final height of the tree you can make the assume  max integer and height value of 32 would cover a majority of usecases. 

In the function I used a query to fetch the max value as I vary the number of calendar years that are genereted during the install while running tests.

Key points to take away from forkNode. 

1. Root is always set to max tree height and the higher the tree the greater the number of loop iterations.
2. Use bisection to iteratre down the tree (divide by 2). 
3. This does not use any disk I/O but recursion will require cpu cycles.
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
To query an intersection we need three result sets.

1. The first set is the values on the left which are guaranteed to overlap with the lower bound that searhing for.Part A - The Fork Node
2. The second is values on the right which are guaranteed to overlap with the upperbound 
3. The last set inner query is not materialized by a procedure. It will find all intervals between the upper and lower bounds of the search.

These procedures use a loop to decend the tree using arithmetic without any I/O operations and when a node is found it is collected in a memory table however since MYSQL procedures can not return inline results the values are instead stored in a temp table using the memory engine to avoid disk I/O.  

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
2. Uses fixed root and bisection to traverse the binary tree.
3. These temp tables are globals.
4. These must be called before the intersect query is executed.

Parts D - Basic Query
--------------------------------------

We have three parts to intersections query

1. Call the right and left nodes procedures to ensure the tmp tables are populated.
2. Execute three select queries (leftQuery,rightQuery,innerQuery) and combine the results.

```mysql

    CALL bm_rules_timeslot_left_nodes(@minslot,@maxslot);
    CALL bm_rules_timeslot_right_nodes(@minslot,@maxslot);


    -- leftQuery
    SELECT i.*
    FROM timeslot_slots_tree i USE INDEX (`idx_timeslot_slots_tree_ri_upper`)
    JOIN timeslot_left_nodes_result l ON i.node = l.node
    AND i.timeslot_id = 1
    -- As where using closed-open interval format we only use '>' as given two intervals p and q that p2 = q1
    -- if we used '>=' operator we would match nodes that qualify as 'meet' allens relation which we don't want.
    AND i.closing_slot_id > @minslot
    UNION ALL
    -- rightQuery
    SELECT i.*
    FROM timeslot_slots_tree i USE INDEX (`idx_timeslot_slots_tree_ri_lower`)
    JOIN timeslot_right_nodes_result l ON i.node = l.node
    AND i.timeslot_id = 1
    AND i.opening_slot_id <= @maxslot
    UNION ALL 
    -- InnerQuery
    SELECT i.*
    FROM timeslot_slots_tree i
    WHERE node BETWEEN @minslot AND @maxslot
    AND i.timeslot_id = 1;
    

```

The leftQuery is different to example found in the paper, my version assumes a closed-open interval relation.

As the optimizer could not produce a stable execution plan I had to specify the indexes to be used but it is these index that make the overall result faster so it is important that they are used in the correct order. 


Parts E - Observation
--------------------------------------
Using the tests in [basic.mysql](basic.mysql) and [normal.mysql](normal.mysql) as a comparision interval query I found that I was able to achieve a large reduction in query time.

Duration(sec):
Normal       : 0.07690900
RITree       : 0.00163325


Part F - Advanced Interval Queries
--------------------------------------------

The authors of the original paper wrote a second paper called "Object-Relational Indexing for GeneralInterval Relationships", and shows how the RI-Tree can be extended to handle the 13 general interval relationships defined by Allen. 

###12 Classes of Nodes

1. topLeft - before,meets,overlaps,finished-by, includes.
2. bottomLeft - before, meets,overlaps.
3. innerLeft - overlaps, starts, during.
4. topRight - includes, started-by, overlaps-By, meets-by, after.
5. bottomRight - overlapped-by, meets-by , after.
6. innerRight - during, finishes, overlaps-by.
7. lower - meets, overlaps, starts.
8. fork - overlaps, finishes-by, includes,starts,equals,finishes,during,started-by,overlapped-by.
9. upper - finishes, meets-by, overlapps-by.
10. allLeft - before.
11. allInner - during.
12. allRight - after.


### Interval Relationships and affected node classes

1. before - allLeft (includes topLeft and bottomLeft)
2. meets - topLeft, bottomLeft,lower
3. overlaps - topLeft,bottomLeft,innerLeft,lower,fork
4. finished-by - topLeft, fork
5. starts - innerLeft, lower, fork
6. includes - topLeft,fork,topRight
7. equals - fork
8. during - allInner (inclusing innerLeft,fork,innerRight)
9. started-by - topRight,fork
10. finishes - innerRight,upper,fork
11. overlapped-by topRight, bottomRight,innerRight,upper,fork
12. meets-by - topRight bottomRight, upper
13.  after - allRight (includes topRight and bottomRight)


### traversal classes, singleton and range classes.

The node classes are grouped into three categories

#### Traversal Classes
1. topLeft
2. bottomLeft
3. innerLeft
4. topRight
5. bottomRight
6. innerRight


These traversal classes need to be materialized with a procedure before they can be
queried as with basic version left nodes and right nodes the binary tree is traversed and
intersection nodes are gathered into tmp tables.


### Singleton Classes
1. fork
2. upper
3. lower
 
These classes are not meterialized though fork must be calculated with exixting forkNode function before 
we can use the value in a query. Queries with these classes are compared using equality match ('=') only
compare against a single value ie singleton.

### Range Classes
1. allLeft  (includes topLeft and bottomLeft)
2. allInner (inclusing innerLeft,fork,innerRight)
3. allRight (includes topRight and bottomRight)

These utilise unions of traversal classes and are comparied using a range comparison ('<','>') operators.
 
1. allLeft:  `node < lower`
2. allInner: `node < lower AND node < upper`
3. allright: `node > upper`


