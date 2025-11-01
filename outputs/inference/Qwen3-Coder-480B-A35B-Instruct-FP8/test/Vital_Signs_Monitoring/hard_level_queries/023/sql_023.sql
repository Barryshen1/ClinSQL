SELECT
  c.*,
  CASE WHEN h.stay_id IS NOT NULL THEN 1 ELSE 0 END AS exposed
FROM
  cohort c
LEFT JOIN
  hfnc_events h
USING
  (stay_id);