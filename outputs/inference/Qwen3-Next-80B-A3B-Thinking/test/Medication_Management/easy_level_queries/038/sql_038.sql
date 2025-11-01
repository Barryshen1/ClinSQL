WITH durations AS (
  SELECT
    TIMESTAMP_DIFF(p.stoptime, p.starttime, 'DAY') AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  ON
    p.hadm_id = adm.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pt
  ON
    p.subject_id = pt.subject_id
  WHERE
    pt.gender = 'M'
    AND (pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year)) BETWEEN 36 AND 46
    AND LOWER(p.drug) = 'digoxin'
    AND p.stoptime IS NOT NULL
)
SELECT
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY duration_days) - 
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY duration_days) AS iqr
FROM durations;