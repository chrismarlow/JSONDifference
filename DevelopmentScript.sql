DECLARE @SourceJSON NVARCHAR(MAX)
DECLARE @TargetJSON NVARCHAR(MAX)
/*
SET @SourceJSON = '{
"list": ["a", "b", "c", {"listx": ["d", "e"]}]
}'

SET @TargetJSON = '{
"list": ["a", "b", {"listx": ["e", "d"]}, "c"]
}'


SET @SourceJSON = '{
"list": [{"a":"1"}, {"b":"2"}],
"list": [{"a":"1"}, {"b":"2"}]
}'

SET @TargetJSON = '{
"list": [{"a":"1"}, {"b":"2"}],
"list": [{"b":"2"},{"a":"1"}]
}'
*/

SET @SourceJSON = '{
"list": ["a", "b", "c", {"listx": ["d", "e"], "listy": ["f"]}]
}'

SET @TargetJSON = '{
"list": ["a", "b", {"listx": ["d", "e"], "listy": ["f"]}, "c"]
}'
/*
SET @SourceJSON = '{
 
  "question": "What is a clustered index?",
  "options": [
    "A bridal cup used in marriage ceremonies by the Navajo indians",
    "a bearing in a gearbox used to facilitate double-declutching",
    "An index that sorts and store the data rows in the table or view based on the key values"
  ],
  "answer": 3
}'

SET @TargetJSON = '{
 
  "question": "What is a clustered index?",
  "options": [
	"a form of mortal combat referred to as ''the noble art of defense''",
    "a bearing in a gearbox used to facilitate double-declutching",
	"A bridal cup used in marriage ceremonies by the Navajo indians",
    "An index that sorts and store the data rows in the table or view based on the key values"
  ],
  "answer": 4
}'
*/
SELECT * FROM dbo.Compare_JsonObject(@SourceJSON, @TargetJSON);
SELECT * FROM dbo.JSONDifference(@SourceJSON, @TargetJSON);