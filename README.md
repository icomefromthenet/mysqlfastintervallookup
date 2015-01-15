Examples of Allens Relations
-------------------------------------------

Using the timslot_slots table for any two intervals 
 
Let p1 = opening_slot_id, p2 = closing_slot_id
 
Let q1 = opening_slot_id, q2 = closing_slot_id
 
Allens Relations
======================

1. equals -> allens/equals.mysql
2. before
3. after
4. meets
5. meets-by
6. overlaps
7. overlaps-by
8. during   -> allens/during.mysql
9. includes -> allens/during.mysql
10. starts -> allens/starts.mysql
11. stared-by -> allens/starts.mysql
12. finishes -> allens/finishes.mysql
13. finished-by -> allens/finishes.mysql

Combinaions
==============
 


The closed:open interval format
------------------------------------ 

There are four ways to represent an interval depending on the inclusion of the
opening and closing values. 

The generally prefered format in database is closed:open a closing interval is always
closing value +1 which actually the opening of the next interval range. 

Two intervals with 5 mintues each [1:6)
open:open     (0:6)
closed:closed [1:5]
open:closed   (0:5]
close:open    [1:6)

closed:open is prefered as it allows a continous range of intervals. If used
open:open the above range would be 1:5 and the next range would be 6:10 there
the gap between the intervals makes queries more difficult.

closed:open range [1:6) has excluded the closing value of 5 in favour of the opening
of the next interval range. The values of the range are 1,2,3,4,5. 

