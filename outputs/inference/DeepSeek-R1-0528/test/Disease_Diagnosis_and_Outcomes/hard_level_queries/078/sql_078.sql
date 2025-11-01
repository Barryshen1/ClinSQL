WITH cohort AS (
  SELECT 
      a.subject_id,
      a.hadm_id,
      a.hospital_expire_flag,
      -- Calculate AKI and ARDS flags
      CASE WHEN EXISTS (
          SELECT 1 
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
          WHERE d.subject_id = a.subject_id 
            AND d.hadm_id = a.hadm_id
            AND (
              (d.icd_version = 9 AND d.icd_code LIKE '584%') 
              OR (d.icd_version = 10 AND d.icd_code LIKE 'N17%')
            )
      ) THEN 1 ELSE 0 END AS aki_flag,
      CASE WHEN EXISTS (
          SELECT 1 
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
          WHERE d.subject_id = a.subject_id 
            AND d.hadm_id = a.hadm_id
            AND (
              (d.icd_version = 9 AND d.icd_code = '518.82') 
              OR (d.icd_version = 10 AND d.icd_code = 'J80')
            )
      ) THEN 1 ELSE 0 END AS ards_flag,
      -- Survival days for in-hospital deaths
      CASE WHEN a.hospital_expire_flag = 1 
          THEN DATE_DIFF(a.deathtime, a.admittime, DAY) 
      END AS survival_days,
      -- Placeholder for composite score (not available)
      CAST(NULL AS FLOAT64) AS composite_score
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE 
      p.gender = 'F'
      AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 59 AND 69
      AND EXISTS (
          SELECT 1 
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_hf
          WHERE d_hf.subject_id = a.subject_id 
            AND d_hf.hadm_id = a.hadm_id
            AND (
              (d_hf.icd_version = 9 AND d_hf.icd_code LIKE '428%') 
              OR (d_hf.icd_version = 10 AND d_hf.icd_code LIKE 'I50%')
            )
      )
)
SELECT
  COUNT(*) AS total_patients,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS mortality_rate,
  AVG(CAST(aki_flag AS FLOAT64)) * 100 AS aki_rate,
  AVG(CAST(ards_flag AS FLOAT64)) * 100 AS ards_rate,
  -- Median survival for deceased patients
  APPROX_QUANTILES(survival_days, 100) [SAFE_OFFSET(50)] AS median_survival_days,
  -- Composite score distribution (not available)
  MIN(composite_score) AS composite_min,
  APPROX_QUANTILES(composite_score, 100) [SAFE_OFFSET(25)] AS composite_p25,
  APPROX_QUANTILES(composite_score, 100) [SAFE_OFFSET(50)] AS composite_median,
  APPROX_QUANTILES(composite_score, 100) [SAFE_OFFSET(75)] AS composite_p75,
  APPROX_QUANTILES(composite_score, 100) [SAFE_OFFSET(90)] AS composite_p90,
  MAX(composite_score) AS composite_max
FROM cohort;