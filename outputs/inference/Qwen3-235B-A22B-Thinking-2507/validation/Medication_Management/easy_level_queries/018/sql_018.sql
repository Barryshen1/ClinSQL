WITH filtered_admissions AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 82 AND 92
),
digoxin_durations AS (
  SELECT 
    TIMESTAMP_DIFF(p.stoptime, p.starttime, SECOND) / (24 * 60 * 60.0) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN filtered_admissions fa
    ON p.hadm_id = fa.hadm_id
  WHERE LOWER(p.drug) LIKE '%digoxin%'
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND p.stoptime >= p.starttime
)
SELECT MAX(duration_days) AS max_duration
FROM digoxin_durations;