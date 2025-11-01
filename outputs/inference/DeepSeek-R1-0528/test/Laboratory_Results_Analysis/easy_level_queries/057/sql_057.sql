WITH male_creatinine AS (
  SELECT 
    le.hadm_id,
    le.valuenum AS creatinine
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON le.subject_id = p.subject_id
  WHERE 
    le.itemid = 50912              -- Serum creatinine
    AND le.valuenum IS NOT NULL    -- Ensure numeric value
    AND le.hadm_id IS NOT NULL     -- Only hospital admissions
    AND p.gender = 'M'             -- Males only
),
nadir_per_admission AS (
  SELECT 
    hadm_id,
    MIN(creatinine) AS nadir_creatinine  -- Nadir = lowest value per stay
  FROM male_creatinine
  GROUP BY hadm_id
)
SELECT 
  APPROX_QUANTILES(nadir_creatinine, 4)[OFFSET(1)] AS q1,  -- 25th percentile
  APPROX_QUANTILES(nadir_creatinine, 4)[OFFSET(3)] AS q3,  -- 75th percentile
  APPROX_QUANTILES(nadir_creatinine, 4)[OFFSET(3)] - APPROX_QUANTILES(nadir_creatinine, 4)[OFFSET(1)] AS iqr  -- IQR (Q3 - Q1)
FROM nadir_per_admission;