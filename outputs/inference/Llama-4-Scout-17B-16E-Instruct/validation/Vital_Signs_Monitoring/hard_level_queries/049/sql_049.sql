WITH data AS (
  SELECT 
    value 
  FROM 
    your_table
)
SELECT 
  COUNTIF(value <= 85) / COUNT(*) 
FROM 
  data;