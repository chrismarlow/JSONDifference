CREATE FUNCTION [dbo].[JSONDifference]
(
	@SourceJSON NVARCHAR(MAX),
	@TargetJSON NVARCHAR(MAX)
	)
/**
Summary: >
  Adapted from https://www.red-gate.com/simple-talk/blogs/sql-server-json-diff-checking-for-differences-between-json-documents/ 
  to cope with different ordering in arrays e.g. where items are added/deleted from an alphabetic list.

  This function 'diffs' a source JSON document with a target JSON document and produces an
  analysis of which properties are missing in either the source or target, or the values
  of these properties that are different. It reports on the properties and values for 
  both source and target as well as the path that references that scalar value. The 
  path reference to the object's parent is exposed in the result to enable a query to
  reference the value of any other object in the parent that is needed. 

Author: Chris Marlow
Date: 22/12/2020

Returns: >
  SideIndicator:  ( == equal, <- not in target, ->  not in source, <> not equal, >< matched item in a different but related position
  PairPath:   the JSON path used by the SQL JSON functions 
  MatchPath:	the JSON path where a match is found (can be different where SideIndicator is ><
  MatchMethod:	One of Object Parent, Object Parent Diff, Pair Reorder or Pair Match depending on which of the 
  PairKey:  the key field without the path
  SourceValue: the value IN the SOURCE JSON document
  TargetValue: the value IN the TARGET JSON document
 
**/
RETURNS @returntable TABLE
--DECLARE @returntable TABLE
	(
		SideIndicator CHAR(2), -- == means equal, <- means not in target, -> means not in source, <> means not equal
		ParentPath  NVARCHAR(2000), --the parent object
		PairPath NVARCHAR(2000), -- the JSON path used by the SQL JSON functions 
		MatchPath NVARCHAR(2000), -- the JSON path used by the SQL JSON functions 
		MatchMethod VARCHAR(20), -- The part of the routine that matched the key/value
		PairKey NVARCHAR(200), --the key field/index in the array without the path
		SourceValue NVARCHAR(200), -- the value IN the SOURCE JSON document
		TargetValue NVARCHAR(200) -- the value IN the TARGET JSON document
	)
AS
BEGIN
    DECLARE @map TABLE --these contain all properties or array elements with scalar values
    (
        [MapID] [int] IDENTITY(1,1) NOT NULL,
		Iteration INT, --the number of times that more arrays or objects were found
        SourceOrTarget CHAR(1), --is this the source 's' OR the target 't'
 		ParentPath NVARCHAR(80), --the parent object
		PairPath NVARCHAR(80), -- the JSON path to the key/value pair or array element
        PairKey NVARCHAR(2000), --the key to the property
        PairValue NVARCHAR(MAX),-- the value
        ValueType INT, --the type of value it is
		MatchPath NVARCHAR(80),
		ObjectID INT,
		MatchMap INT,
		MatchMethod VARCHAR(20)
    );
        
	DECLARE @objects TABLE --this contains all the properties with arrays and objects 
    (
		ObjectID [int] IDENTITY(1,1) NOT NULL,
		Iteration INT,
		SourceOrTarget CHAR(1),
		ParentPath NVARCHAR(80),
		PairPath NVARCHAR(80),
		PairKey NVARCHAR(2000),
		PathValue NVARCHAR(MAX),
		ValueType INT,
		PairDepth INT,
		MatchObject INT,
		ParentObject INT,
		ParentMatch BIT
	);

	--Start expanding from the top of nesting
	DECLARE @Depth INT = 1; 
    DECLARE @HowManyObjectsNext INT = 1, @SourceType INT, @TargetType INT, @ObjectID INT, @MatchObjectID INT, @MapID INT, @TempCounter INT, @StopTarget BIT, @ObjectIDSource int,@ObjectIDTarget int, @FetchMapGroupSource int, @FetchMapGroupTarget int;;
    
	--Firstly, we try to work out if the source is an array or object
	SELECT 
          @SourceType = 
            CASE IsNumeric((SELECT TOP 1 [key] FROM OpenJson(@SourceJSON))) 
              WHEN 1 THEN 4 ELSE 5 END,
          @TargetType= --and if the target is an array or object
            CASE IsNumeric((SELECT TOP 1 [key] FROM OpenJson(@TargetJSON))) 
              WHEN 1 THEN 4 ELSE 5 END
    
	--Insert the base objects or arrays into the object table      
    INSERT INTO @objects 
          (Iteration, SourceOrTarget, ParentPath, PairPath, PairKey, PathValue, ValueType, MatchObject, ParentMatch)
          SELECT 0, 's' AS SourceOrTarget,'' AS parent, '$' AS path, '', @SourceJSON, @SourceType,
			CASE 
				WHEN @SourceJSON=@TargetJSON THEN 2 ELSE Null
			END,
			CASE 
				WHEN @SourceJSON=@TargetJSON THEN 1 ELSE 0
			END;
    INSERT INTO @objects 
          (Iteration, SourceOrTarget,ParentPath, PairPath, PairKey, PathValue, ValueType, MatchObject, ParentMatch)
          SELECT 0, 't' AS SourceOrTarget, '' AS parent, '$' AS path,
          '', @TargetJSON, @TargetType,
			CASE 
				WHEN @SourceJSON=@TargetJSON THEN 1 ELSE Null
			END,
			CASE 
				WHEN @SourceJSON=@TargetJSON THEN 1 ELSE 0
			END;
        
	--These setting ensure the iteration is run once
    SELECT @Depth = 0, @HowManyObjectsNext = 2; 
		
		WHILE @HowManyObjectsNext > 0
			BEGIN
  
				--Get the scalar values into the @map table
				INSERT INTO @map 
					(Iteration, SourceOrTarget, ParentPath, PairPath, PairKey, PairValue, ValueType, ObjectID)
				SELECT -- 
					o.Iteration + 1, SourceOrTarget,
					PairPath,
					PairPath+CASE ValueType WHEN 4 THEN '['+[Key]+']' ELSE '.'+[key] END, 
					[key],[value],[type], ObjectID
				FROM @objects AS o
					CROSS APPLY OpenJson(PathValue)
				WHERE Type IN (1, 2, 3) AND o.Iteration = @Depth;
			
				--Expand nested objects and arrays
				INSERT INTO @objects (Iteration, SourceOrTarget, ParentPath, PairPath, PairKey, PathValue, ValueType, PairDepth, ParentObject, ParentMatch)
				SELECT o.Iteration + 1, SourceOrTarget,PairPath,
					PairPath + CASE ValueType WHEN 4 THEN '['+[Key]+']' ELSE '.'+[Key] END,
					[key],[value],[type],@Depth ,ObjectID, 
					CASE WHEN MatchObject Is Null THEN 0 ELSE 1 END
				FROM @objects o 
				CROSS APPLY OpenJson(PathValue) 
				WHERE type IN (4,5) AND o.Iteration=@Depth  
				
				--Update how many objects or arrays in the next level in nesting
				SELECT @HowManyObjectsNext=@@RowCount

				--Cascade matching where parent objects match
				UPDATE o
				SET MatchObject=mo.ObjectID
				FROM @objects o
					INNER JOIN @objects mo ON (o.PathValue=mo.PathValue)
					INNER JOIN @objects op ON (o.ParentObject=op.ObjectID)
					INNER JOIN @objects mp ON (mo.ParentObject=mp.ObjectID)
				WHERE op.MatchObject=mp.ObjectID
				

				--Where the parent objects are not matched, but paths do match, use cursor to only update 1st match
				DECLARE ObjectCursorNotParent CURSOR FOR
				SELECT ObjectID FROM @objects WHERE SourceOrTarget='s' AND PairDepth=@Depth AND MatchObject Is Null AND ParentMatch=0 ORDER BY ObjectID

				OPEN ObjectCursorNotParent;  
  
					-- Perform the first fetch.  
					FETCH NEXT FROM ObjectCursorNotParent INTO @ObjectID;  
  
					-- Check @@FETCH_STATUS to see if there are any more rows to fetch.  
					WHILE @@FETCH_STATUS = 0  
						BEGIN  
						--
						--PICK and update the first matching ID where PathValue is the same and SourceOrTarget=t, mark up successful match							
						SELECT @MatchObjectID=MIN(o.ObjectID)
						FROM @objects o
						LEFT JOIN @objects op on o.ParentObject=op.ObjectID
						WHERE o.MatchObject Is Null 
							AND o.PairDepth=@Depth And o.SourceOrTarget='t' 
							AND o.PathValue=(SELECT PathValue FROM @objects WHERE ObjectID=@ObjectID) 
							AND o.ParentPath=(SELECT ParentPath FROM @objects WHERE ObjectID=@ObjectID)
						
						UPDATE @objects
						SET MatchObject=@ObjectID
						WHERE ObjectID=@MatchObjectID

						IF (@@ROWCOUNT=1)
						BEGIN
							UPDATE @objects
							SET MatchObject=(SELECT ObjectID FROM @objects WHERE MatchObject=@ObjectID)
							WHERE ObjectID=@ObjectID
						END

						FETCH NEXT FROM ObjectCursorNotParent INTO @ObjectID;

					END  
  
				CLOSE ObjectCursorNotParent;  
				DEALLOCATE ObjectCursorNotParent; 

				--Move down a level update/match @Map objects at this level
				SELECT @Depth=@Depth+1 

				--Update MatchMap/MatchPath for matched Objects
				UPDATE m 
				SET m.MatchMap=mp.MapID, m.MatchPath=mp.PairPath, 
					m.MatchMethod=CASE o.ParentMatch WHEN 1 THEN 'Object Parent' ELSE 'Object Parent Diff' END
				FROM @map m INNER JOIN @objects o ON m.ObjectID=o.ObjectID
				INNER JOIN @map mp ON mp.ObjectID=o.MatchObject
				WHERE m.Iteration=@Depth and m.PairValue=mp.PairValue
				
				--Now look for sets by ObjectID where all @Map items match
				DECLARE MapGroupSource CURSOR FOR
				SELECT DISTINCT ObjectID 
				FROM @map m 
				WHERE m.SourceOrTarget='s' AND m.Iteration=@Depth AND m.MatchPath Is Null AND (SELECT COUNT(*) FROM @map WHERE Not MatchPath Is Null AND ParentPath=m.ParentPath)=0
				OPEN MapGroupSource;

					FETCH NEXT FROM MapGroupSource INTO @ObjectIDSource;
					SET @FetchMapGroupSource=@@FETCH_STATUS
					
					WHILE @FetchMapGroupSource = 0  
						
						BEGIN  

						SET @StopTarget=0;
						DECLARE MapGroupTarget CURSOR FOR
						SELECT DISTINCT ObjectID 
						FROM @map m 
						WHERE m.SourceOrTarget='t' AND m.Iteration=@Depth AND m.MatchPath Is Null AND (SELECT COUNT(*) FROM @map WHERE Not MatchPath Is Null AND ParentPath=m.ParentPath)=0
						OPEN MapGroupTarget;

							FETCH NEXT FROM MapGroupTarget INTO @ObjectIDTarget;
							SET @FetchMapGroupTarget=@@FETCH_STATUS
							
							WHILE @FetchMapGroupTarget = 0 AND @StopTarget = 0
								BEGIN  
					
								--Count mismatches both ways (don't need to check intersection as if no intersection there will be mismatches)
								SELECT @TempCounter=COUNT(*)
								FROM
									--Source not in target
									((SELECT PairValue FROM @map WHERE ObjectID=@ObjectIDSource AND Iteration=@Depth
									EXCEPT
									SELECT PairValue FROM @map WHERE ObjectID=@ObjectIDTarget AND Iteration=@Depth)
									UNION
									--Target not in source
									(SELECT PairValue FROM @map WHERE ObjectID=@ObjectIDTarget AND Iteration=@Depth
									EXCEPT
									SELECT PairValue FROM @map WHERE ObjectID=@ObjectIDSource AND Iteration=@Depth)) AS UNI
								--No mismatches implies a match
								IF @TempCounter=0
								BEGIN

									--Update source and target with the match
									UPDATE m
									SET m.MatchPath=mp.PairPath, MatchMap=mp.MapID, MatchMethod = 'Pair Reorder'
									FROM @map m
										INNER JOIN @map mp ON m.PairValue=mp.PairValue
									WHERE m.ObjectID=@ObjectIDSource AND mp.ObjectID=@ObjectIDTarget 
										AND m.SourceOrTarget='s' AND mp.SourceOrTarget='t'
										AND m.Iteration=@Depth AND mp.Iteration=@Depth

									UPDATE m
									SET m.MatchPath=mp.PairPath, MatchMap=mp.MapID, MatchMethod = 'Pair Reorder'
									FROM @map m
										INNER JOIN @map mp ON m.PairValue=mp.PairValue
									WHERE m.ObjectID=@ObjectIDTarget AND mp.ObjectID=@ObjectIDSource 
										AND m.SourceOrTarget='t' AND mp.SourceOrTarget='s'
										AND m.Iteration=@Depth AND mp.Iteration=@Depth
										
									--Exit the cursor to stop source being used more than once
									SET @StopTarget=1;

								END
							
							FETCH NEXT FROM MapGroupTarget INTO @ObjectIDTarget;
							SET @FetchMapGroupTarget=@@FETCH_STATUS
							
							END

						CLOSE MapGroupTarget;  
						DEALLOCATE MapGroupTarget; 

						FETCH NEXT FROM MapGroupSource INTO @ObjectIDSource;
						SET @FetchMapGroupSource=@@FETCH_STATUS
							
					END

				CLOSE MapGroupSource;  
				DEALLOCATE MapGroupSource;

				--Now try to match strings not matched by containing object
				DECLARE MapCursor CURSOR FOR
				SELECT MapID FROM @map m WHERE m.SourceOrTarget='s' AND m.Iteration=@Depth AND m.MatchMap Is Null ORDER BY MapID

				OPEN MapCursor;  
  
					-- Perform the first fetch.  
					FETCH NEXT FROM MapCursor INTO @MapID;  
  
					-- Check @@FETCH_STATUS to see if there are any more rows to fetch.  
					WHILE @@FETCH_STATUS = 0  
						BEGIN  
						--
						--PICK and update the first matching ID where PathValue is the same and SourceOrTarget=t, mark up successful match
						UPDATE @map
						SET MatchPath=(SELECT PairPath FROM @map WHERE MapID=@MapID), MatchMethod = 'Pair Match'
						WHERE 
							MapID=(SELECT MIN(MapID) FROM @map WHERE MatchPath Is Null 
								AND Iteration=@Depth And SourceOrTarget='t' 
								AND PairKey = (SELECT PairKey FROM @map WHERE MapID=@MapID)
								AND PairValue=(SELECT PairValue FROM @map WHERE MapID=@MapID) 
								AND ParentPath=(SELECT ParentPath FROM @map WHERE MapID=@MapID))
						IF (@@ROWCOUNT=1)
						BEGIN
							UPDATE @map
							SET MatchPath=(SELECT PairPath FROM @map WHERE MatchPath=(SELECT PairPath FROM @map WHERE MapID=@MapID) AND Iteration=@Depth AND SourceOrTarget='t'), MatchMethod = 'Pair Match'
							WHERE MapID=@MapID
						END
						--SELECT * FROM @objects WHERE ObjectID=@ObjectID
						FETCH NEXT FROM MapCursor INTO @MapID;
					END  
  
				CLOSE MapCursor;  
				DEALLOCATE MapCursor; 
 
         END
	
	--Full outer join on the unmatched items
	INSERT INTO @returntable (SideIndicator, ParentPath, PairPath, PairKey, SourceValue, TargetValue)
	SELECT 
		--Side indicator that summarises the comparison
		CASE WHEN SourceJSON.PairValue=TargetJSON.PairValue THEN '=='
			ELSE 
			CASE  WHEN SourceJSON.PairPath IS NULL THEN '-' ELSE '<' end
			+ CASE WHEN TargetJSON.PairPath IS NULL THEN '-' ELSE '>' END 
		END AS Sideindicator, 
		--The attribute fields could be in either table
		Coalesce(SourceJSON.ParentPath, TargetJSON.ParentPath) AS ParentPath,
		Coalesce(SourceJSON.PairPath, TargetJSON.PairPath) AS PairPath,
		Coalesce(SourceJSON.PairKey, TargetJSON.PairKey) AS PairKey,
		--Return the values
		SourceJSON.PairValue, TargetJSON.PairValue
		FROM 
			(SELECT MapID, ParentPath, PairPath, PairKey, PairValue, MatchPath FROM @map WHERE SourceOrTarget = 's' AND MatchPath Is Null)
				AS SourceJSON -- Source scalar literals
			FULL OUTER JOIN 
			(SELECT MapID, ParentPath, PairPath, PairKey, PairValue, MatchPath FROM @map WHERE SourceOrTarget = 't' AND MatchPath Is Null)
				AS TargetJSON --Target scalar literals
			ON SourceJSON.PairPath = TargetJSON.PairPath;
	
	--Matched items we have all the detail we need on source records
	INSERT INTO @returntable (SideIndicator, ParentPath, PairPath, MatchPath, MatchMethod, PairKey, SourceValue, TargetValue)
	SELECT 
		CASE WHEN PairPath=MatchPath THEN '==' ELSE '><' END AS SideIndicator, 
		ParentPath, PairPath, MatchPath, MatchMethod, PairKey, PairValue, PairValue
	FROM @map
	WHERE SourceOrTarget='s' AND
		NOT MatchPath Is Null;
	RETURN; 
END
