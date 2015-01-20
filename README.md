Examples of Allens Relations
===============================

Using the timslot_slots table for any two intervals 
 
Let p1 = opening_slot_id, p2 = closing_slot_id
Let q1 = opening_slot_id, q2 = closing_slot_id
 
Allens Relations
-----------------------

1. equals -> [allens/equals.mysql](src/allens/equals.mysql)
2. before -> [allens/before.mysql](src/allens/before.mysql)
3. after  -> [allens/before.mysql](src/allens/before.mysql)
4. meets  -> [allens/meets.mysql](src/allens/meets.mysql)
5. meets-by -> [allens/meets.mysql](src/allens/meets.mysql) 
6. overlaps -> [allens/overlaps.mysql](src/allens/overlaps.mysql)
7. overlaps-by [allens/overlaps.mysql](src/allens/overlaps.mysql)
8. during   -> [allens/during.mysql](src/allens/during.mysql)
9. includes -> [allens/during.mysql](src/allens/during.mysql)
10. starts -> [allens/starts.mysql](src/allens/starts.mysql)
11. stared-by -> [allens/starts.mysql](src/allens/starts.mysql)
12. finishes -> [allens/finishes.mysql](src/allens/finishes.mysql)
13. finished-by -> [allens/finishes.mysql](src/allens/finishes.mysql)

Combinaions
------------------------
 
 1. Aligns     -> [combine/aligns.mysql](src/combine/aligns.mysql)
 2. Excludes   -> [combine/excludes.mysql](src/combine/excludes.mysql)
 3. Fills      -> [combine/fills.mysql](src/combine/fills.mysql)
 4. Intersects -> [combine/intersects.mysql](src/combine/intersects.mysql)
 5. occupies   -> [combine/occupies.mysql](src/combine/occupies.mysql)


The closed:open interval format
==================================== 

There are four ways to represent an interval depending on the inclusion of the
opening and closing values. 

The generally prefered format in database is closed:open a closing interval is always
closing value +1 which actually the opening of the next range. 

Two intervals with 5 mintues each
open:open     (0:6)
closed:closed [1:5]
open:closed   (0:5]
close:open    [1:6)

The closed:open is prefered as it allows a continous range of intervals to be easily searched. If closed:closed is used
the above range would be [1:5] and the next range would be [6:10]. Its easier to build a continous set
if the intervals p[1:6) & q[6:11) we can match 'p2=q1'. 
If we used closed-closed we would need to know the length of the clock tick between intervals so we could write a query like '(p2 - q1) = clock-tick'

RI Tree
===================================== 

The Relation Interval Tree is an adaption of and Interval Tree structure into
a relational context. 

I have implement a simple version with fixed height tree.

The table `timeslot_slots_tree` tree has been modifed to support the RITree. It is
based on the original `timeslot_slots` table.

An example of every day query can be found in [tree/basic.mysql](src/tree/basic.mysql). A comparision query 
of common interval search can be found in [tree/normal.mysql](src/tree/normal.mysql).

Using a low teir VPS hosted with Linode, running both queries to find intersection of timeslots
within a particular calendar day.

Duration(sec):
Normal       : 0.076909
RITree       : 0.00163325

The RITree was able to significantly speed up the intersects query. 


