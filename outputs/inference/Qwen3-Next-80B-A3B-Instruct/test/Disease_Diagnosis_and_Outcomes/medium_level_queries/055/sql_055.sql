SELECT 
  i.subject_id,
  i.hadm_id,
  0 AS has_mv,  -- explicitly 0 for mv
  MAX(CASE WHEN ... THEN 1 ELSE 0 END) AS has_vasopressor,
  0 AS has_rrt;