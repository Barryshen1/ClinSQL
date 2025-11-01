WITH qualifying_adm AS (
  -- Cardiac arrest admissions: females 59-69
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    p.dod,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND (
      (d.icd_version = 9 AND d.icd_code = '4275')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I46%')
    )
),
risk_and_comps AS (
  -- Add risk score (distinct ICD count) and complication flags
  SELECT
    q.*,
    COUNT(DISTINCT d_all.icd_code) AS risk_score,
    MAX(CASE WHEN
      (
        (d_all.icd_version = 10 AND (
          d_all.icd_code LIKE 'I21%' OR
          d_all.icd_code LIKE 'I50%' OR
          d_all.icd_code = 'R570' OR
          d_all.icd_code LIKE 'I971%'
        ))
        OR
        (d_all.icd_version = 9 AND (
          d_all.icd_code LIKE '410%' OR
          d_all.icd_code LIKE '428%' OR
          d_all.icd_code = '78551'
        ))
      )
      AND NOT (
        (d_all.icd_version = 10 AND d_all.icd_code LIKE 'I46%')
        OR (d_all.icd_version = 9 AND d_all.icd_code = '4275')
      )
    THEN 1 ELSE 0 END) AS has_cv_comp,
    MAX(CASE WHEN
      (
        (d_all.icd_version = 10 AND (
          d_all.icd_code LIKE 'I60%' OR d_all.icd_code LIKE 'I61%' OR
          d_all.icd_code LIKE 'I62%' OR d_all.icd_code LIKE 'I63%' OR
          d_all.icd_code LIKE 'I64%' OR d_all.icd_code LIKE 'G40%' OR
          d_all.icd_code LIKE 'G41%' OR d_all.icd_code LIKE 'G45%'
        ))
        OR
        (d_all.icd_version = 9 AND (
          d_all.icd_code LIKE '430%' OR d_all.icd_code LIKE '431%' OR
          d_all.icd_code LIKE '432%' OR d_all.icd_code LIKE '433%' OR
          d_all.icd_code LIKE '434%' OR d_all.icd_code LIKE '345%'
        ))
      )
    THEN 1 ELSE 0 END) AS has_neuro_comp
  FROM qualifying_adm q
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_all
    ON q.subject_id = d_all.subject_id AND q.hadm_id = d_all.hadm_id
  GROUP BY
    q.subject_id, q.hadm_id, q.admittime, q.dischtime, q.deathtime, q.dod, q.anchor_age
),
stratified AS (
  -- Add 30-day death flag and quartile
  SELECT
    *,
    CASE
      WHEN dod IS NOT NULL AND DATE(dod) <= DATE_ADD(DATE(admittime), INTERVAL 30 DAY)
      THEN 1 ELSE 0
    END AS dead_30d_flag,
    CAST(NTILE(4) OVER (ORDER BY risk_score) AS STRING) AS quartile
  FROM risk_and_comps
),
-- Cardiac cohort metrics per quartile
cardiac_metrics AS (
  SELECT
    quartile,
    COUNT(*) AS n,
    SAFE_DIVIDE(SUM(dead_30d_flag), COUNT(*)) AS mortality_30d,
    SAFE_DIVIDE(SUM(has_cv_comp), COUNT(*)) AS cv_comp_rate,
    SAFE_DIVIDE(SUM(has_neuro_comp), COUNT(*)) AS neuro_comp_rate
  FROM stratified
  GROUP BY quartile
),
cardiac_survivors AS (
  SELECT
    quartile,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days
  FROM stratified
  WHERE dead_30d_flag = 0
),
cardiac_medians AS (
  SELECT
    quartile,
    APPROX_QUANTILES(los_days, 100)[SAFE_OFFSET(50)] AS median_survivor_los
  FROM cardiac_survivors
  GROUP BY quartile
),
-- Baseline: all female 59-69 admissions
baseline_adm AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    p.dod
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
),
baseline_flags AS (
  SELECT
    *,
    CASE
      WHEN dod IS NOT NULL AND DATE(dod) <= DATE_ADD(DATE(admittime), INTERVAL 30 DAY)
      THEN 1 ELSE 0
    END AS dead_30d_flag
  FROM baseline_adm
),
baseline_metrics AS (
  SELECT
    'baseline' AS quartile,
    COUNT(*) AS n,
    SAFE_DIVIDE(SUM(dead_30d_flag), COUNT(*)) AS mortality_30d,
    NULL AS cv_comp_rate,
    NULL AS neuro_comp_rate,
    NULL AS median_survivor_los
  FROM baseline_flags
)
-- Combine: quartiles + baseline
SELECT
  cm.quartile,
  cm.n,
  cm.mortality_30d,
  cm.cv_comp_rate,
  cm.neuro_comp_rate,
  cmed.median_survivor_los
FROM cardiac_metrics cm
LEFT JOIN cardiac_medians cmed
  ON cm.quartile = cmed.quartile

UNION ALL

SELECT * FROM baseline_metrics

ORDER BY quartile;