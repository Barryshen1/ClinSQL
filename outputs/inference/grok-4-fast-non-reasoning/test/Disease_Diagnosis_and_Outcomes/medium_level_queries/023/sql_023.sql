WITH cohort AS (
  -- Base cohort: female, age 52-62, with stroke diagnosis
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    CASE 
      WHEN REGEXP_CONTAINS(icd.icd_code, r'^I63') THEN 'Ischemic'
      WHEN REGEXP_CONTAINS(icd.icd_code, r'^(I60|I61|I62)') THEN 'Hemorrhagic'
    END AS stroke_type
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` icd 
    ON a.hadm_id = icd.hadm_id AND icd.icd_version = 'ICD-10-CM'
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
    AND p.anchor_age IS NOT NULL
    AND (REGEXP_CONTAINS(icd.icd_code, r'^I63') OR REGEXP_CONTAINS(icd.icd_code, r'^(I60|I61|I62)'))
    AND a.admittime < a.dischtime  -- valid admission
    AND icd.seq_num = 1  -- Primary diagnosis for stroke type
    AND NOT EXISTS (
      -- Ensure no mixed stroke types in this admission
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` icd2 
      WHERE icd2.hadm_id = a.hadm_id 
        AND icd2.icd_version = 'ICD-10-CM'
        AND icd2.seq_num <= 5  -- Check top 5 diagnoses
        AND (
          (REGEXP_CONTAINS(icd2.icd_code, r'^I63') AND stroke_type = 'Hemorrhagic') OR
          (REGEXP_CONTAINS(icd2.icd_code, r'^(I60|I61|I62)') AND stroke_type = 'Ischemic')
        )
    )
),

overall_stats AS (
  -- Pre-compute overall median LOS for categorization
  SELECT 
    APPROX_QUANTILES(los, 2)[OFFSET(1)] AS median_los
  FROM cohort
),

comorbidity_scores AS (
  -- Compute total non-stroke comorbidity count per patient
  SELECT 
    c.subject_id,
    COUNT(DISTINCT diag.icd_code) AS comm_score,
    NTILE(3) OVER (ORDER BY COUNT(DISTINCT diag.icd_code)) AS comm_tertile
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
    ON c.subject_id = diag.subject_id AND c.hadm_id = diag.hadm_id
    AND diag.icd_version = 'ICD-10-CM'
    -- Exclude stroke codes for pure comorbidity score
    AND NOT (REGEXP_CONTAINS(diag.icd_code, r'^I63') OR REGEXP_CONTAINS(diag.icd_code, r'^(I60|I61|I62)'))
  GROUP BY c.subject_id
),

ckd_diabetes AS (
  -- Flag CKD and diabetes per hadm_id
  SELECT 
    c.hadm_id,
    MAX(CASE WHEN REGEXP_CONTAINS(d.icd_code, r'^N18') THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN REGEXP_CONTAINS(d.icd_code, r'^(E10|E11|E12|E13|E14)') THEN 1 ELSE 0 END) AS has_diabetes
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON c.hadm_id = d.hadm_id AND d.icd_version = 'ICD-10-CM'
  GROUP BY c.hadm_id
),

final_cohort AS (
  SELECT 
    c.*,
    cs.comm_tertile,
    cd.has_ckd,
    cd.has_diabetes,
    -- LOS category based on overall median
    CASE WHEN c.los < os.median_los THEN 'Short' ELSE 'Long' END AS los_category
  FROM cohort c
  CROSS JOIN overall_stats os
  INNER JOIN comorbidity_scores cs ON c.subject_id = cs.subject_id
  INNER JOIN ckd_diabetes cd ON c.hadm_id = cd.hadm_id
  WHERE c.stroke_type IS NOT NULL
)

-- Aggregate outcomes
SELECT 
  stroke_type,
  comm_tertile,
  -- Mortality %
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_pct,
  -- Median LOS by group
  ROUND(PERCENTILE_CONT(0.5, los), 2) AS median_los_days,
  -- LOS distribution (<8 vs >=8 days)
  ROUND(AVG(CASE WHEN los < 8 THEN 1.0 ELSE 0 END) * 100, 2) AS pct_los_less_8,
  ROUND(AVG(CASE WHEN los >= 8 THEN 1.0 ELSE 0 END) * 100, 2) AS pct_los_ge_8,
  -- Comorbidity prevalences
  ROUND(AVG(has_ckd) * 100, 2) AS ckd_prevalence_pct,
  ROUND(AVG(has_diabetes) * 100, 2) AS diabetes_prevalence_pct,
  -- Sample size
  COUNT(*) AS n_admissions
FROM final_cohort
GROUP BY stroke_type, comm_tertile
ORDER BY stroke_type, comm_tertile;