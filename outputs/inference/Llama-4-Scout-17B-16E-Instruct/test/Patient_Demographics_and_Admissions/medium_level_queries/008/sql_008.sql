WITH 
  -- ... (rest of the CTEs remain the same)

SELECT 
  discharge_type,
  AVG(los) AS mean_los,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY los) AS median_los,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY los) AS p75_los,
  PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY los) AS p90_los,
  PERCENT_RANK() OVER (PARTITION BY discharge_type ORDER BY los) AS percentile_rank_7days
FROM 
  los_data
WHERE 
  los = 7
GROUP BY 
  discharge_type;