SELECT
  AVG(DATETIME_DIFF(p.stoptime, p.starttime, DAY)) AS avg_duration_days
FROM
  `physionet-data.mimiciv_3_1_hosp.prescriptions` p
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON p.subject_id = pat.subject_id
WHERE
  LOWER(p.drug) LIKE '%digoxin%'  -- Digoxin filter
  AND pat.gender = 'M'  -- Male patients
  AND p.stoptime IS NOT NULL  -- Must have end time
  AND p.stoptime >= p.starttime  -- Valid time range
  AND EXTRACT(YEAR FROM p.starttime) - (pat.anchor_year - pat.anchor_age) 
      BETWEEN 66 AND 76;  -- Age 66-76 at prescription time;