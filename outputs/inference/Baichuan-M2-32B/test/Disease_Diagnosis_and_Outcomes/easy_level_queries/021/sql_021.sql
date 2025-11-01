WITH cohort_admissions AS (
    SELECT 
      a.hadm_id,
      a.admittime,
      a.dischtime,
      TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    WHERE p.gender = 'F'
      AND p.anchor_age BETWEEN 58 AND 68
      AND a.dischtime IS NOT NULL
      -- We'll filter diagnoses in the next step
  ),
  admissions_with_diagnoses AS (
    SELECT 
      c.hadm_id,
      c.los_days
    FROM cohort_admissions c
    INNER JOIN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE icd_version = 10
      GROUP BY hadm_id
      HAVING 
        SUM(CASE WHEN icd_code LIKE 'I60%' OR icd_code LIKE 'I61%' OR icd_code LIKE 'I62%' THEN 1 ELSE 0 END) > 0
        AND SUM(CASE WHEN icd_code LIKE 'J44%' THEN 1 ELSE 0 END) > 0
    ) d ON c.hadm_id = d.hadm_id
  )
  SELECT 
    APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS p25,
    APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75,
    APPROX_QUANTILES(los_days, 100)[OFFSET(75)] - APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS iqr
  FROM admissions_with_diagnoses;