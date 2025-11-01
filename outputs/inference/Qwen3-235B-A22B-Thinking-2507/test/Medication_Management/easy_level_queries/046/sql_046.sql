WITH drug_prescriptions AS (
  SELECT 
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  WHERE 
    (LOWER(p.drug) LIKE '%spironolactone%' OR LOWER(p.drug) LIKE '%eplerenone%')
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND p.stoptime >= p.starttime
),
with_admission AS (
  SELECT 
    dp.*,
    a.admittime
  FROM drug_prescriptions dp
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON dp.hadm_id = a.hadm_id
),
with_patient AS (
  SELECT 
    wa.*,
    pat.gender,
    pat.anchor_age,
    pat.anchor_year
  FROM with_admission wa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON wa.subject_id = pat.subject_id
),
with_age AS (
  SELECT 
    *,
    anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year) AS age_at_admission
  FROM with_patient
),
filtered AS (
  SELECT 
    *,
    TIMESTAMP_DIFF(stoptime, starttime, SECOND) / 86400.0 AS duration_days
  FROM with_age
  WHERE 
    gender = 'M'
    AND age_at_admission BETWEEN 90 AND 100
),
ranked AS (
  SELECT 
    duration_days,
    ROW_NUMBER() OVER (ORDER BY duration_days) AS rn,
    COUNT(*) OVER () AS cnt
  FROM filtered
)
SELECT 
  AVG(duration_days) AS median_duration_days
FROM ranked
WHERE rn IN (FLOOR((cnt + 1) / 2), CEIL((cnt + 1) / 2));