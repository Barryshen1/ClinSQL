WITH comorbidity_counts AS (
  SELECT 
    hadm_id,
    COUNT(DISTINCT comorbidity) AS comorbidity_count
  FROM (
    SELECT 
      diag.hadm_id,
      CASE
        -- Elixhauser Comorbidity Mapping (AHRQ) - Simplified example
        WHEN diag.icd_code LIKE 'I098%' OR diag.icd_code LIKE 'I11%' OR diag.icd_code LIKE 'I13%' OR diag.icd_code LIKE 'I25%' OR diag.icd_code LIKE 'I42%' OR diag.icd_code LIKE 'I43%' OR diag.icd_code LIKE 'I50%' THEN 'CHF'
        WHEN diag.icd_code LIKE 'I44%' OR diag.icd_code LIKE 'I45%' OR diag.icd_code LIKE 'I47%' OR diag.icd_code LIKE 'I48%' OR diag.icd_code LIKE 'I49%' THEN 'Arrhythmia'
        WHEN diag.icd_code LIKE 'I70%' OR diag.icd_code LIKE 'I71%' OR diag.icd_code LIKE 'I73%' OR diag.icd_code LIKE 'I77%' OR diag.icd_code LIKE 'I79%' OR diag.icd_code LIKE 'K55%' OR diag.icd_code LIKE 'Z95%' THEN 'PVD'
        -- Add all other Elixhauser categories here for a complete implementation
        ELSE NULL
      END AS comorbidity
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    WHERE diag.icd_version = 10
  )
  WHERE comorbidity IS NOT NULL
  GROUP BY hadm_id
),

cohort AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- Calculate LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- Categorize LOS
    CASE WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) <= 5 THEN 'LOS ≤5'
         ELSE 'LOS >5' END AS los_category,
    -- Check if ICU stay exists
    CASE WHEN i.stay_id IS NOT NULL THEN 'ICU' ELSE 'non-ICU' END AS icu_status,
    -- Get comorbidity count
    COALESCE(cc.comorbidity_count, 0) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  -- Left join to icustays to determine ICU status (moved before WHERE)
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  -- Join to comorbidity counts
  LEFT JOIN comorbidity_counts cc
    ON a.hadm_id = cc.hadm_id
  -- Filter for male, age 82-92, and post-op complications
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 82 AND 92
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE icd_code LIKE 'T81%'
        AND icd_version = 10
    )
),

-- Bin comorbidities
cohort_with_bins AS (
  SELECT *,
    CASE 
      WHEN comorbidity_count <= 1 THEN '0-1'
      WHEN comorbidity_count = 2 THEN '2'
      ELSE '≥3' 
    END AS comorbidity_bin
  FROM cohort
)

-- Aggregate by ICU status, LOS category, and comorbidity bin
SELECT 
  icu_status,
  los_category,
  comorbidity_bin,
  COUNT(*) AS n,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS in_hospital_mortality_percent,
  ROUND(AVG(comorbidity_count), 2) AS avg_comorbidity_count
FROM cohort_with_bins
GROUP BY icu_status, los_category, comorbidity_bin
ORDER BY icu_status, los_category, comorbidity_bin;