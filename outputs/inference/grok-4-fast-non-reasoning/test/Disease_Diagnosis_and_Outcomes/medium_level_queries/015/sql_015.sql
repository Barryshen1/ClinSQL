WITH stroke_admissions AS (
  -- Filter to female stroke admissions aged 48-58
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    -- LOS in days (using TIMESTAMP_DIFF for precision)
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- Primary stroke diagnosis (ICD-10 I60-I64)
    diag.icd_code AS primary_icd
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.subject_id = diag.subject_id 
    AND a.hadm_id = diag.hadm_id
    AND diag.seq_num = 1
    AND diag.icd_version = '10'
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
    AND REGEXP_CONTAINS(diag.icd_code, '^I6[0-4]')
    AND a.hospital_expire_flag IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) > 0
),
icu_flags AS (
  -- Flag ICU vs non-ICU admissions
  SELECT 
    sa.*,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.transfers` t
        WHERE t.subject_id = sa.subject_id 
          AND t.hadm_id = sa.hadm_id 
          AND t.eventtype = 'admit'
          AND t.careunit IS NOT NULL
          AND (t.careunit LIKE 'ICU%' OR t.careunit LIKE 'CCU%')
      ) THEN 'ICU'
      ELSE 'Non-ICU'
    END AS icu_group
  FROM stroke_admissions sa
),
comorbidity_flags AS (
  -- Add comorbidity burden via DRG severity proxy
  SELECT 
    ifl.*,
    CASE 
      WHEN drg.drg_severity IS NULL OR drg.drg_code IS NULL THEN 'None'
      WHEN drg.drg_severity <= 2 THEN 'Low'
      ELSE 'High'
    END AS comorbidity_burden
  FROM icu_flags ifl
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.drgcodes` drg
    ON ifl.subject_id = drg.subject_id 
    AND ifl.hadm_id = drg.hadm_id
    AND drg.drg_type = 'HC'  -- MS-DRG, most common
),
grouped_data AS (
  -- Group by all dimensions
  SELECT 
    icu_group,
    CASE WHEN los_days <= 5 THEN 'LOS ≤5' ELSE 'LOS >5' END AS los_group,
    comorbidity_burden,
    COUNT(*) AS total_admissions,
    SUM(CAST(hospital_expire_flag AS INT64)) AS deaths
  FROM comorbidity_flags
  GROUP BY icu_group, los_group, comorbidity_burden
),
mortality_stats AS (
  -- Calculate mortality % and 95% CI (Wilson score interval)
  SELECT 
    *,
    SAFE_DIVIDE(deaths, total_admissions) * 100.0 AS mortality_pct,
    -- Wilson CI lower bound
    SAFE_DIVIDE(
      (deaths + (1.96 * 1.96 / 2)) - 1.96 * SAFE_SQRT((1.96 * 1.96 / 4) + SAFE_DIVIDE(deaths * (total_admissions - deaths), total_admissions)) / total_admissions,
      1 + (1.96 * 1.96 / total_admissions)
    ) * 100.0 AS ci_lower,
    -- Wilson CI upper bound
    SAFE_DIVIDE(
      (deaths + (1.96 * 1.96 / 2)) + 1.96 * SAFE_SQRT((1.96 * 1.96 / 4) + SAFE_DIVIDE(deaths * (total_admissions - deaths), total_admissions)) / total_admissions,
      1 + (1.96 * 1.96 / total_admissions)
    ) * 100.0 AS ci_upper
  FROM grouped_data
  WHERE total_admissions > 0  -- Avoid div-by-zero
)
SELECT 
  icu_group,
  los_group,
  comorbidity_burden,
  total_admissions,
  deaths,
  ROUND(mortality_pct, 2) AS mortality_pct,
  ROUND(ci_lower, 2) AS ci_lower_95,
  ROUND(ci_upper, 2) AS ci_upper_95
FROM mortality_stats
ORDER BY 
  icu_group, 
  CASE WHEN los_group = 'LOS ≤5' THEN 1 ELSE 2 END,
  CASE 
    WHEN comorbidity_burden = 'None' THEN 1 
    WHEN comorbidity_burden = 'Low' THEN 2 
    ELSE 3 
  END;