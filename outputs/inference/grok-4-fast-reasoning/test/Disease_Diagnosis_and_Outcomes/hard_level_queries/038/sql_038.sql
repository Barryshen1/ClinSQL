WITH base_cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.dod,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS admission_age,
    CASE WHEN aki.subject_id IS NOT NULL THEN 1 ELSE 0 END AS has_aki
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  LEFT JOIN (
    SELECT DISTINCT subject_id, hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE (icd_version = 9 AND icd_code LIKE '584%')
       OR (icd_version = 10 AND icd_code LIKE 'N17.%')
  ) aki ON a.subject_id = aki.subject_id AND a.hadm_id = aki.hadm_id
  WHERE p.gender = 'M'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 74 AND 84
),
mortality_cohort AS (
  SELECT *,
    CASE 
      WHEN deathtime IS NOT NULL AND deathtime <= TIMESTAMP_ADD(admittime, INTERVAL 30 DAY) THEN 1
      WHEN deathtime IS NULL AND dod IS NOT NULL 
           AND dod <= DATE_ADD(DATE(admittime), INTERVAL 30 DAY) THEN 1
      ELSE 0
    END AS thirty_day_death
  FROM base_cohort
),
drg_cohort AS (
  SELECT 
    mc.*,
    CAST(dc.drg_mortality AS INT64) AS risk_score
  FROM mortality_cohort mc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.drgcodes` dc
    ON mc.subject_id = dc.subject_id 
    AND mc.hadm_id = dc.hadm_id 
    AND dc.drg_type = 'MS'
),
ards_cohort AS (
  SELECT 
    dc.*,
    CASE WHEN ar.subject_id IS NOT NULL THEN 1 ELSE 0 END AS has_ards
  FROM drg_cohort dc
  LEFT JOIN (
    SELECT DISTINCT subject_id, hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE (icd_version = 9 AND icd_code = '51882')
       OR (icd_version = 10 AND icd_code = 'J80')
  ) ar ON dc.subject_id = ar.subject_id AND dc.hadm_id = ar.hadm_id
),
los_cohort AS (
  SELECT *,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los_days
  FROM ards_cohort
),
general_risks AS (
  SELECT ARRAY_AGG(risk_score IGNORE NULLS) AS all_risks
  FROM los_cohort
),
aki_stats AS (
  SELECT 
    'AKI Cohort' AS cohort_type,
    COUNT(*) AS n_admissions,
    APPROX_QUANTILES(risk_score, 100)[OFFSET(50)] AS median_risk_score,
    APPROX_QUANTILES(risk_score, 100)[OFFSET(25)] AS risk_iqr_lower,
    APPROX_QUANTILES(risk_score, 100)[OFFSET(75)] AS risk_iqr_upper,
    AVG(CAST(thirty_day_death AS FLOAT64)) AS thirty_day_mortality_rate,
    AVG(CAST(has_ards AS FLOAT64)) AS ards_rate,
    APPROX_QUANTILES(IF(thirty_day_death = 0, CAST(los_days AS FLOAT64), NULL), 1)[OFFSET(0)] AS median_survivor_los_days,
    NULL AS risk_percentile
  FROM los_cohort
  WHERE has_aki = 1
),
general_stats AS (
  SELECT 
    'General Cohort' AS cohort_type,
    COUNT(*) AS n_admissions,
    NULL AS median_risk_score,
    NULL AS risk_iqr_lower,
    NULL AS risk_iqr_upper,
    NULL AS thirty_day_mortality_rate,
    AVG(CAST(has_ards AS FLOAT64)) AS ards_rate,
    APPROX_QUANTILES(IF(thirty_day_death = 0, CAST(los_days AS FLOAT64), NULL), 1)[OFFSET(0)] AS median_survivor_los_days,
    NULL AS risk_percentile
  FROM los_cohort
),
combined AS (
  SELECT * FROM aki_stats
  UNION ALL
  SELECT * FROM general_stats
)
SELECT 
  c.* EXCEPT(risk_percentile),
  CASE 
    WHEN c.cohort_type = 'AKI Cohort' AND c.median_risk_score IS NOT NULL AND ARRAY_LENGTH(gr.all_risks) > 0 THEN
      (SELECT COUNTIF(r <= c.median_risk_score) FROM UNNEST(gr.all_risks) r) * 100.0 / ARRAY_LENGTH(gr.all_risks)
    ELSE NULL 
  END AS risk_percentile
FROM combined c
CROSS JOIN general_risks gr
ORDER BY cohort_type;