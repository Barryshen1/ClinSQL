WITH patients_age AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- Compute age at admission
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admission,
    a.admission_type
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
-- Filter inpatient types
inpatient_admissions AS (
  SELECT *
  FROM patients_age
  WHERE admission_type IN ('ELECTIVE', 'EMERGENCY', 'URGENT')
    AND age_at_admission BETWEEN 46 AND 56
),
-- AMI diagnosis: ICD-10 I21 or ICD-9 410
ami_cohort AS (
  SELECT DISTINCT ia.*
  FROM inpatient_admissions ia
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON ia.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE (d.icd_version = 9 AND d.icd_code LIKE '410%')
     OR (d.icd_version = 10 AND d.icd_code LIKE 'I21%')
),
-- Major complications: define list of ICD codes for complications
complication_codes AS (
  SELECT 'I46' AS icd_code, 9 AS icd_version UNION ALL
  SELECT '427.5', 9 UNION ALL
  SELECT 'R57.0', 10 UNION ALL
  SELECT 'I50', 10 UNION ALL
  SELECT 'I49.01', 10 UNION ALL
  SELECT 'R09.02', 10
),
-- Patients with major complications in same admission
complications AS (
  SELECT DISTINCT ac.hadm_id
  FROM ami_cohort ac
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON ac.hadm_id = di.hadm_id
  INNER JOIN complication_codes cc
    ON di.icd_code = cc.icd_code AND di.icd_version = cc.icd_version
),
-- Final cohort with composite risk score
cohort_with_score AS (
  SELECT
    ac.*,
    DATETIME_DIFF(ac.dischtime, ac.admittime, SECOND) / (24*60*60) AS los_days,
    COALESCE(c.hadm_id IS NOT NULL, FALSE) AS has_major_complication,
    ac.age_at_admission + (CASE WHEN c.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS composite_risk_score
  FROM ami_cohort ac
  LEFT JOIN complications c ON ac.hadm_id = c.hadm_id
),
-- Assign quintiles
quintiles AS (
  SELECT *,
    NTILE(5) OVER (ORDER BY composite_risk_score) AS risk_quintile
  FROM cohort_with_score
)
-- Final aggregation
SELECT
  risk_quintile,
  -- In-hospital mortality %
  ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100, 2) AS mortality_pct,
  -- Major complication %
  ROUND(AVG(CAST(has_major_complication AS INT64)) * 100, 2) AS complication_pct,
  -- Median survivor LOS (in days)
  ROUND(APPROX_QUANTILES(CASE WHEN hospital_expire_flag = 0 THEN los_days END, 100)[OFFSET(50)], 2) AS median_survivor_los_days
FROM quintiles
GROUP BY risk_quintile
ORDER BY risk_quintile;