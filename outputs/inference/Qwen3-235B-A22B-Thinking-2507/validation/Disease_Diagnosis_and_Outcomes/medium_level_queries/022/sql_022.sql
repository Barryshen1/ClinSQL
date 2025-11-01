WITH patients_of_interest AS (
  SELECT 
    p.subject_id,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- Calculate precise age at admission
    TIMESTAMP_DIFF(a.admittime, 
                  DATETIME(p.anchor_year, 1, 1, 0, 0, 0), 
                  YEAR) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND TIMESTAMP_DIFF(a.admittime, 
                      DATETIME(p.anchor_year, 1, 1, 0, 0, 0), 
                      YEAR) BETWEEN 50 AND 60
)
, sepsis_patients AS (
  SELECT 
    poi.*
  FROM patients_of_interest poi
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    WHERE di.hadm_id = poi.hadm_id
      AND di.icd_version = 10
      AND (di.icd_code LIKE 'A40%' OR di.icd_code LIKE 'A41%')
  )
  AND NOT EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    WHERE di.hadm_id = poi.hadm_id
      AND di.icd_version = 10
      AND di.icd_code IN ('R65.21', 'A40.21', 'A41.21', 'A41.31', 
                         'A41.41', 'A41.51', 'A41.81', 'A41.91')
  )
)
, icu_status AS (
  SELECT 
    sp.*,
    -- Check ICU overlap with first 24h of admission
    CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END AS icu_day1
  FROM sepsis_patients sp
  LEFT JOIN `physionet-data.mimiciv_3_1_icu`.icustays i
    ON sp.hadm_id = i.hadm_id
    AND i.intime < TIMESTAMP_ADD(sp.admittime, INTERVAL 1 DAY)
    AND (i.outtime > sp.admittime OR i.outtime IS NULL)
)
, final_cohort AS (
  SELECT 
    *,
    -- Calculate LOS in days
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days,
    -- Determine LOS category
    CASE WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) <= 7 
         THEN '≤7 days' 
         ELSE '>7 days' 
    END AS los_category
  FROM icu_status
)
SELECT
  los_category,
  icu_day1,
  COUNT(*) AS n_patients,
  AVG(hospital_expire_flag) * 100 AS mortality_rate,
  APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los
FROM final_cohort
GROUP BY los_category, icu_day1
ORDER BY los_category, icu_day1;