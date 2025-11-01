WITH cohort AS (
  -- Select male inpatients aged 35-45 with acute pancreatitis
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.anchor_age,
    pat.gender,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      ON adm.hadm_id = diag.hadm_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 35 AND 45
    AND (
      -- Acute pancreatitis ICD-10: K85*, ICD-9: 5770
      (diag.icd_version = 10 AND diag.icd_code LIKE 'K85%')
      OR (diag.icd_version = 9 AND diag.icd_code = '5770')
    )
),
diagnosis_counts AS (
  -- Count diagnoses per admission
  SELECT
    hadm_id,
    COUNT(*) AS diagnosis_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY
    hadm_id
),
major_complications AS (
  -- Flag major complications per admission
  SELECT
    diag.hadm_id,
    MAX(
      CASE
        -- Acute renal failure
        WHEN (diag.icd_version = 10 AND diag.icd_code LIKE 'N17%')
          OR (diag.icd_version = 9 AND diag.icd_code LIKE '584%') THEN 1
        -- Sepsis
        WHEN (diag.icd_version = 10 AND diag.icd_code LIKE 'A41%')
          OR (diag.icd_version = 9 AND (diag.icd_code IN ('99591','99592') OR diag.icd_code LIKE '038%')) THEN 1
        -- ARDS
        WHEN (diag.icd_version = 10 AND diag.icd_code = 'J80')
          OR (diag.icd_version = 9 AND diag.icd_code = '51882') THEN 1
        -- GI bleeding
        WHEN (diag.icd_version = 10 AND diag.icd_code = 'K922')
          OR (diag.icd_version = 9 AND diag.icd_code LIKE '578%') THEN 1
        -- Shock
        WHEN (diag.icd_version = 10 AND diag.icd_code LIKE 'R57%')
          OR (diag.icd_version = 9 AND diag.icd_code LIKE '7855%') THEN 1
        ELSE 0
      END
    ) AS major_complication_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  GROUP BY
    diag.hadm_id
),
base AS (
  -- Assemble cohort with diagnosis count and major complication flag
  SELECT
    c.subject_id,
    c.hadm_id,
    c.anchor_age,
    c.gender,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    COALESCE(dc.diagnosis_count, 0) AS diagnosis_count,
    COALESCE(mc.major_complication_flag, 0) AS major_complication_flag,
    TIMESTAMP_DIFF(c.dischtime, c.admittime, HOUR)/24.0 AS los_days
  FROM
    cohort c
    LEFT JOIN diagnosis_counts dc ON c.hadm_id = dc.hadm_id
    LEFT JOIN major_complications mc ON c.hadm_id = mc.hadm_id
),
risk_scores AS (
  -- Calculate risk score and assign quartile
  SELECT
    *,
    (diagnosis_count + 5 * major_complication_flag) AS risk_score,
    NTILE(4) OVER (ORDER BY (diagnosis_count + 5 * major_complication_flag)) AS risk_quartile
  FROM
    base
),
quartile_stats AS (
  -- Aggregate stats per quartile
  SELECT
    risk_quartile,
    COUNT(*) AS n_admissions,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS in_hospital_mortality_rate,
    SUM(major_complication_flag) / COUNT(*) AS major_complication_rate,
    APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_survivor_los_days
  FROM
    risk_scores
  WHERE
    hospital_expire_flag = 0 -- survivors for LOS
  GROUP BY
    risk_quartile
),
overall_stats AS (
  -- Aggregate overall stats
  SELECT
    'Overall' AS risk_quartile,
    COUNT(*) AS n_admissions,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS in_hospital_mortality_rate,
    SUM(major_complication_flag) / COUNT(*) AS major_complication_rate,
    APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_survivor_los_days
  FROM
    risk_scores
  WHERE
    hospital_expire_flag = 0
)
SELECT
  CAST(risk_quartile AS STRING) AS risk_quartile,
  n_admissions,
  in_hospital_mortality_rate,
  major_complication_rate,
  median_survivor_los_days
FROM
  quartile_stats
UNION ALL
SELECT
  risk_quartile,
  n_admissions,
  in_hospital_mortality_rate,
  major_complication_rate,
  median_survivor_los_days
FROM
  overall_stats
ORDER BY
  CASE WHEN risk_quartile = 'Overall' THEN 5 ELSE CAST(risk_quartile AS INT64) END
;