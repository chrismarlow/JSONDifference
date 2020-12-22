# JSONDifference
SQL Server Functions for getting differences between JSON

  JSONDifference function is adapted from original Compare_JsonObject at;
  https://www.red-gate.com/simple-talk/blogs/sql-server-json-diff-checking-for-differences-between-json-documents/ 
  to cope with different ordering in arrays e.g. where items are added/deleted from an alphabetic list.

  This function 'diffs' a source JSON document with a target JSON document and produces an
  analysis of which properties are missing in either the source or target, or the values
  of these properties that are different. It reports on the properties and values for 
  both source and target as well as the path that references that scalar value. The 
  path reference to the object's parent is exposed in the result to enable a query to
  reference the value of any other object in the parent that is needed. 
  
 Returns: >
  SideIndicator:  ( == equal, <- not in target, ->  not in source, <> not equal, >< matched item in a different but related position
  PairPath:   the JSON path used by the SQL JSON functions 
  MatchPath:	the JSON path where a match is found (can be different where SideIndicator is ><
  MatchMethod:	One of Object Parent, Object Parent Diff, Pair Reorder or Pair Match depending on which of the 
  PairKey:  the key field without the path
  SourceValue: the value IN the SOURCE JSON document
  TargetValue: the value IN the TARGET JSON document
