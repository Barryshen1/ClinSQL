WITH cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 80 AND 90
    AND (
      (di.icd_version = 9 AND (di.icd_code LIKE '038%' OR di.icd_code = '785.52'))
      OR
      (di.icd_version = 10 AND (di.icd_code LIKE 'A40%' OR di.icd_code LIKE 'A41%' OR di.icd_code LIKE 'R65.2%'))
    )
),
med_orders AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    pr.drug,
    pr.starttime
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.subject_id = pr.subject_id AND c.hadm_id = pr.hadm_id
  WHERE pr.starttime >= c.admittime
    AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 1 DAY)
),
med_summary AS (
  SELECT
    m.hadm_id,
    COUNT(DISTINCT m.drug) AS med_complexity_score,
    MAX(CASE WHEN LOWER(m.drug) LIKE '%amiodarone%' OR LOWER(m.drug) LIKE '%haloperidol%' OR
             LOWER(m.drug) LIKE '%ondansetron%' OR LOWER(m.drug) LIKE '%ciprofloxacin%' OR
             LOWER(m.drug) LIKE '%levofloxacin%' OR LOWER(m.drug) LIKE '%azithromycin%' OR
             LOWER(m.drug) LIKE '%fluconazole%' OR LOWER(m.drug) LIKE '%methadone%'
        THEN 1 ELSE 0 END) AS has_qt,
    MAX(CASE WHEN LOWER(m.drug) LIKE '%warfarin%' OR LOWER(m.drug) LIKE '%heparin%' OR
             LOWER(m.drug) LIKE '%enoxaparin%' OR LOWER(m.drug) LIKE '%aspirin%' OR
             LOWER(m.drug) LIKE '%clopidogrel%' OR LOWER(m.drug) LIKE '%rivaroxaban%' OR
             LOWER(m.drug) LIKE '%apixaban%'
        THEN 1 ELSE 0 END) AS has_bleeding
  FROM med_orders m
  GROUP BY m.hadm_id
),
patient_data AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.anchor_age,
    c.los_days,
    c.hospital_expire_flag,
    COALESCE(ms.med_complexity_score, 0) AS med_complexity_score,
    CASE WHEN COALESCE(ms.has_qt, 0) = 1 AND COALESCE(ms.has_bleeding, 0) = 1
         THEN 'both' ELSE 'other' END AS risk_group
  FROM cohort c
  LEFT JOIN med_summary ms
    ON c.hadm_id = ms.hadm_id
),
summary_by_group AS (
  SELECT
    risk_group,
    COUNT(*) AS n_patients,
    ROUND(AVG(med_complexity_score), 2) AS mean_score,
    MIN(med_complexity_score) AS min_score,
    MAX(med_complexity_score) AS max_score,
    APPROX_QUANTILES(med_complexity_score, 4)[OFFSET(0)] AS score_q1,
    APPROX_QUANTILES(med_complexity_score, 4)[OFFSET(1)] AS score_median,
    APPROX_QUANTILES(med_complexity_score, 4)[OFFSET(2)] AS score_q3
  FROM patient_data
  GROUP BY risk_group
),
top_quartile AS (
  SELECT
    COUNT(*) AS n_patients,
    ROUND(AVG(med_complexity_score), 2) AS mean_score,
    ROUND(AVG(los_days), 2) AS avg_los_days,
    ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100, 2) AS mortality_rate_percent
  FROM patient_data
  WHERE med_complexity_score >= (
    SELECT APPROX_QUANTILES(med_complexity_score, 4)[OFFSET(2)]
    FROM patient_data
  )
)
SELECT
  risk_group,
  n_patients,
  mean_score,
  min_score,
  max_score,
  score_q1,
  score_median,
  score_q3,
  NULL AS avg_los_days,
  NULL AS mortality_rate_percent
FROM summary_by_group

UNION ALL

SELECT
  'top_quartile_overall' AS risk_group,
  n_patients,
  mean_score,
  NULL AS min_score,
  NULL AS max_score,
  NULL AS score_q1,
  NULL AS score_median,
  NULL AS score_q3,
  avg_los_days,
  mortality_rate_percent
FROM top_quartile

ORDER BY risk_group;