WITH base_pop AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.gender,
    -- approximate age at admission
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age_at_adm,
    adm.admittime,
    adm.dischtime,
    pat.dod,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat USING (subject_id)
  WHERE pat.gender = 'M'
),
pop74_84 AS (
  SELECT *
  FROM base_pop
  WHERE age_at_adm BETWEEN 74 AND 84
),
aki_flag AS (
  SELECT DISTINCT
    diags.subject_id,
    diags.hadm_id,
    1 AS aki
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diags
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddesc
    ON diags.icd_code = ddesc.icd_code
    AND diags.icd_version = ddesc.icd_version
  WHERE ( (diags.icd_version = 9 AND diags.icd_code LIKE '584%')
       OR (diags.icd_version = 10 AND diags.icd_code LIKE 'N17%') )
),
ards_flag AS (
  SELECT DISTINCT
    diags.subject_id,
    diags.hadm_id,
    1 AS ards
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diags
  WHERE ( (diags.icd_version = 9 AND diags.icd_code = '51882')
       OR (diags.icd_version = 10 AND diags.icd_code = 'J80') )
),
risk_scores AS (
  -- Placeholder for real risk score extraction
  SELECT
    subject_id,
    SAFE_CAST(result_value AS FLOAT64) AS risk_score
  FROM `physionet-data.mimiciv_3_1_hosp.omr`
  WHERE LOWER(result_name) LIKE '%risk score%'
)
,
pop_with_flags AS (
  SELECT
    p.*,
    IF(aki.aki IS NOT NULL, 1, 0) AS aki,
    IF(ards.ards IS NOT NULL, 1, 0) AS ards,
    rs.risk_score,
    -- 30-day mortality flag
    CASE
      WHEN p.dod IS NULL THEN 0
      WHEN p.dod <= p.admittime + INTERVAL 30 DAY THEN 1 ELSE 0
    END AS mort_30d,
    -- LOS in days
    TIMESTAMP_DIFF(p.dischtime, p.admittime, DAY) AS los_days
  FROM pop74_84 p
  LEFT JOIN aki_flag aki
    ON p.subject_id = aki.subject_id AND p.hadm_id = aki.hadm_id
  LEFT JOIN ards_flag ards
    ON p.subject_id = ards.subject_id AND p.hadm_id = ards.hadm_id
  LEFT JOIN risk_scores rs
    ON p.subject_id = rs.subject_id
)
,
aki_group AS (
  SELECT *
  FROM pop_with_flags
  WHERE aki = 1
),
general_group AS (
  SELECT *
  FROM pop_with_flags
  WHERE aki = 0
),
aki_summary AS (
  SELECT
    'AKI' AS group_name,
    COUNT(*) AS n,
    APPROX_QUANTILES(risk_score, 100)[OFFSET(50)] AS median_risk,
    APPROX_QUANTILES(risk_score, 100)[OFFSET(25)] AS q1,
    APPROX_QUANTILES(risk_score, 100)[OFFSET(75)] AS q3,
    ROUND(100 * SUM(mort_30d)/COUNT(*),2) AS mort30d_pct,
    ROUND(100 * SUM(ards)/COUNT(*),2) AS ards_rate_pct,
    AVG(CASE WHEN mort_30d=0 THEN los_days END) AS mean_los_survivors
  FROM aki_group
),
general_summary AS (
  SELECT
    'General' AS group_name,
    COUNT(*) AS n,
    NULL AS median_risk,
    NULL AS q1,
    NULL AS q3,
    NULL AS mort30d_pct,
    ROUND(100 * SUM(ards)/COUNT(*),2) AS ards_rate_pct,
    AVG(CASE WHEN mort_30d=0 THEN los_days END) AS mean_los_survivors
  FROM general_group
),
risk_percentile_for_79yo AS (
  SELECT
    '79yo_index_patient' AS label,
    rs.risk_score,
    ROUND(100 * SUM(CASE WHEN g.risk_score <= rs.risk_score THEN 1 ELSE 0 END)/COUNT(*), 2) AS percentile_rank
  FROM aki_group g
  JOIN (
    SELECT risk_score
    FROM aki_group
    WHERE age_at_adm = 79
    LIMIT 1
  ) rs
  ON TRUE
  GROUP BY rs.risk_score
)
SELECT * FROM aki_summary
UNION ALL
SELECT * FROM general_summary
UNION ALL
SELECT label AS group_name, NULL, risk_score, NULL, NULL, percentile_rank, NULL, NULL
FROM risk_percentile_for_79yo;