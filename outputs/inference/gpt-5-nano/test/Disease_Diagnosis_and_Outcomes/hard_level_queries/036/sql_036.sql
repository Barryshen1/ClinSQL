WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    -- comorbidity_count: number of distinct non-pneumonia diagnoses for this admission
    COUNT(DISTINCT CASE
                     WHEN NOT (
                       di.icd_code LIKE '480%' OR di.icd_code LIKE '481%' OR di.icd_code LIKE '482%' OR
                       di.icd_code LIKE '483%' OR di.icd_code LIKE '484%' OR di.icd_code LIKE '485%' OR di.icd_code LIKE '486%'
                     )
                     THEN di.icd_code
                   END) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id
   AND di.hadm_id = a.hadm_id
  WHERE p.gender = 'Male'
    AND p.anchor_age BETWEEN 73 AND 83
    -- pneumonia presence in this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di2
      WHERE di2.subject_id = a.subject_id
        AND di2.hadm_id = a.hadm_id
        AND (di2.icd_code LIKE '480%' OR di2.icd_code LIKE '481%' OR di2.icd_code LIKE '482%' OR
             di2.icd_code LIKE '483%' OR di2.icd_code LIKE '484%' OR di2.icd_code LIKE '485%' OR di2.icd_code LIKE '486%')
    )
  GROUP BY a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag, p.gender, p.anchor_age
)

-- 75th percentile of comorbidity_count across the cohort
, p75 AS (
  SELECT PERCENTILE_CONT(comorbidity_count, 0.75) OVER () AS p75_value
  FROM cohort
  LIMIT 1
)

-- Mark top-quartile comorbidity admissions
, cohort_top AS (
  SELECT c.*,
         CASE WHEN c.comorbidity_count >= p75.p75_value THEN 1 ELSE 0 END AS top_quartile_flag
  FROM cohort AS c
  CROSS JOIN p75
)

-- Compute flags and survival days for the final cohort
, final AS (
  SELECT
    ct.subject_id,
    ct.hadm_id,
    ct.admittime,
    ct.dischtime,
    ct.hospital_expire_flag,
    ct.gender,
    ct.anchor_age,
    ct.comorbidity_count,
    CASE WHEN ct.hospital_expire_flag = 1 THEN 1 ELSE 0 END AS mortality_flag,
    -- Major complications flag (defined by presence of high-severity ICD-9 codes)
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di3
      WHERE di3.subject_id = ct.subject_id
        AND di3.hadm_id = ct.hadm_id
        AND (
          di3.icd_code LIKE '410%' OR di3.icd_code LIKE '411%' OR    -- AMI
          di3.icd_code LIKE '428%' OR                             -- Heart failure
          di3.icd_code LIKE '430%' OR di3.icd_code LIKE '431%' OR di3.icd_code LIKE '434%' OR di3.icd_code LIKE '435%' OR -- Stroke
          di3.icd_code LIKE '584%' OR di3.icd_code LIKE '585%' OR    -- AKI/CKD
          di3.icd_code LIKE '518%' OR di3.icd_code LIKE '518.5%' OR -- Respiratory failure/ARDS
          di3.icd_code LIKE '038%' OR di3.icd_code LIKE '9959%' OR di3.icd_code LIKE '7855%' -- Sepsis and Shock indicators
        )
    ) THEN 1 ELSE 0 END AS major_complication_flag,
    TIMESTAMP_DIFF(ct.dischtime, ct.admittime, DAY) AS survival_days
  FROM cohort_top ct
  WHERE ct.top_quartile_flag = 1
)

-- Final select: per-patient row with percentile and cohort-wide metrics
SELECT
  f.subject_id,
  f.hadm_id,
  f.admittime,
  f.dischtime,
  f.anchor_age,
  f.mortality_flag,
  f.major_complication_flag,
  f.survival_days,
  -- Composite risk percentile based on comorbidity_count within the top-quartile cohort
  100 * PERCENT_RANK() OVER (ORDER BY f.comorbidity_count DESC) AS composite_risk_percentile,
  -- Cohort-wide metrics (same value across all rows for readability)
  100 * AVG(f.mortality_flag) OVER () AS in_hospital_mortality_percent,
  100 * AVG(f.major_complication_flag) OVER () AS major_complication_percent,
  PERCENTILE_CONT(f.survival_days, 0.5) OVER () AS median_survival_days
FROM final AS f
-- Focus on the 78-year-old male as the specific patient of interest
WHERE f.anchor_age = 78
ORDER BY f.subject_id, f.hadm_id
;