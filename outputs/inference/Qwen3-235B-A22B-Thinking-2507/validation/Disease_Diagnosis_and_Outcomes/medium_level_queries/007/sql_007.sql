WITH 
-- Count secondary diagnoses (seq_num > 1) per admission for comorbidity proxy
diagnoses_count AS (
  SELECT 
    hadm_id,
    COUNTIF(seq_num > 1) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),

-- Identify mechanical ventilation (ICU procedures only)
mv_flag_cte AS (
  SELECT DISTINCT 
    pe.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  WHERE 
    LOWER(di.label) LIKE '%ventilat%' 
    OR LOWER(di.label) LIKE '%intubat%'
),

-- Identify vasopressor administration (ICU inputs + ward prescriptions)
vaso_flag_cte AS (
  -- ICU vasopressors (fixed: joined with d_items to access label)
  SELECT DISTINCT ie.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ie.itemid = di.itemid
  WHERE 
    LOWER(di.label) LIKE '%norepinephrine%'
    OR LOWER(di.label) LIKE '%epinephrine%'
    OR LOWER(di.label) LIKE '%phenylephrine%'
    OR LOWER(di.label) LIKE '%vasopressin%'
  UNION DISTINCT
  -- Ward vasopressors (unchanged: prescriptions has drug column)
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE 
    LOWER(drug) LIKE '%norepinephrine%'
    OR LOWER(drug) LIKE '%epinephrine%'
    OR LOWER(drug) LIKE '%phenylephrine%'
    OR LOWER(drug) LIKE '%vasopressin%'
),

-- Identify RRT (ICU procedures + ward HCPCS codes) - FIXED: removed invalid subquery
rrt_flag_cte AS (
  -- ICU RRT
  SELECT DISTINCT pe.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  WHERE 
    LOWER(di.label) LIKE '%dialysis%'
    OR LOWER(di.label) LIKE '%crrt%'
    OR LOWER(di.label) LIKE '%hemodialysis%'
  UNION DISTINCT
  -- Ward RRT (common dialysis HCPCS codes)
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
  WHERE hcpcs_cd IN ('90935', '90937', '90945', '90947', '90993', '90996')
),

-- Base cohort: Female 51-61 with heart failure
cohort AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- Age calculation per MIMIC-IV documentation
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age,
    -- ICU flag
    CASE WHEN i.stay_id IS NOT NULL THEN 'yes' ELSE 'no' END AS icu,
    -- LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los,
    -- Comorbidity count (default 0 if no secondary diagnoses)
    COALESCE(dc.comorbidity_count, 0) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  LEFT JOIN diagnoses_count dc
    ON a.hadm_id = dc.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  WHERE 
    p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 51 AND 61
    -- Heart failure diagnosis (ICD-9: 428%, ICD-10: I50%)
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE 
        a.hadm_id = d.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '428%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
        )
    )
),

-- Categorize LOS and comorbidity burden
cohort_categorized AS (
  SELECT 
    hadm_id,
    icu,
    CASE WHEN los < 8 THEN '<8' ELSE '>=8' END AS los_category,
    CASE 
      WHEN comorbidity_count = 0 THEN 'low'
      WHEN comorbidity_count BETWEEN 1 AND 2 THEN 'medium'
      ELSE 'high' 
    END AS comorbidity_burden,
    hospital_expire_flag
  FROM cohort
),

-- Add intervention flags
cohort_with_flags AS (
  SELECT 
    c.hadm_id,
    c.icu,
    c.los_category,
    c.comorbidity_burden,
    c.hospital_expire_flag,
    COALESCE(mv.hadm_id IS NOT NULL, FALSE) AS mv_flag,
    COALESCE(v.hadm_id IS NOT NULL, FALSE) AS vaso_flag,
    COALESCE(r.hadm_id IS NOT NULL, FALSE) AS rrt_flag
  FROM cohort_categorized c
  LEFT JOIN mv_flag_cte mv ON c.hadm_id = mv.hadm_id
  LEFT JOIN vaso_flag_cte v ON c.hadm_id = v.hadm_id
  LEFT JOIN rrt_flag_cte r ON c.hadm_id = r.hadm_id
),

-- Compute group-level metrics - FIXED: cast booleans to INT64 for AVG
mortality_rates AS (
  SELECT 
    icu,
    los_category,
    comorbidity_burden,
    COUNT(*) AS n,
    SUM(hospital_expire_flag) AS deaths,
    AVG(hospital_expire_flag) AS mortality_rate,
    AVG(CAST(mv_flag AS INT64)) AS mv_prevalence,
    AVG(CAST(vaso_flag AS INT64)) AS vaso_prevalence,
    AVG(CAST(rrt_flag AS INT64)) AS rrt_prevalence
  FROM cohort_with_flags
  GROUP BY icu, los_category, comorbidity_burden
),

-- Extract non-ICU mortality rates for difference calculations
non_icu_rates AS (
  SELECT 
    los_category,
    comorbidity_burden,
    mortality_rate AS non_icu_mortality_rate
  FROM mortality_rates
  WHERE icu = 'no'
)

-- Final output with mortality rates, differences, and intervention prevalence
SELECT 
  m.icu,
  m.los_category,
  m.comorbidity_burden,
  m.n,
  m.deaths,
  m.mortality_rate,
  m.mv_prevalence,
  m.vaso_prevalence,
  m.rrt_prevalence,
  -- Absolute difference (ICU - non-ICU within stratum)
  CASE 
    WHEN m.icu = 'yes' THEN m.mortality_rate - n.non_icu_mortality_rate 
    ELSE NULL 
  END AS abs_diff,
  -- Relative difference (ICU vs non-ICU within stratum)
  CASE 
    WHEN m.icu = 'yes' AND n.non_icu_mortality_rate > 0 
      THEN (m.mortality_rate - n.non_icu_mortality_rate) / n.non_icu_mortality_rate 
    ELSE NULL 
  END AS rel_diff
FROM mortality_rates m
LEFT JOIN non_icu_rates n 
  ON m.los_category = n.los_category 
  AND m.comorbidity_burden = n.comorbidity_burden
ORDER BY 
  m.los_category, 
  m.comorbidity_burden, 
  m.icu;