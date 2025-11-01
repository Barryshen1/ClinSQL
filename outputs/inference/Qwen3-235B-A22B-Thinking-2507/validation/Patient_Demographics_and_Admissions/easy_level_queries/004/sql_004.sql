WITH first_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
)
SELECT 
  STDDEV(TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0) AS std_los_days
FROM first_admissions
WHERE rn = 1
  AND gender = 'F'
  AND age_at_admission >= 70
  AND age_at_admission <= 80;