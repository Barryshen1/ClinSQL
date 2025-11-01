WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_hosp
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
),
labs_72h AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    dl.label,
    l.flag
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON l.itemid = dl.itemid
  JOIN cohort c
    ON l.subject_id = c.subject_id
    AND l.hadm_id = c.hadm_id
  WHERE l.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
    AND LOWER(l.flag) = 'abnormal'
),
score_per_patient AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.anchor_age,
    c.gender,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    c.los_hosp,
    COUNT(*) AS lab_instability_score
  FROM cohort c
  LEFT JOIN labs_72h l
    ON c.subject_id = l.subject_id
    AND c.hadm_id = l.hadm_id
  GROUP BY c.subject_id, c.hadm_id, c.anchor_age, c.gender, c.admittime, c.dischtime, c.hospital_expire_flag, c.los_hosp
),
p90_val AS (
  SELECT
    PERCENTILE_CONT(lab_instability_score, 0.9) OVER() AS p90_score
  FROM score_per_patient
  LIMIT 1
),
top_tier AS (
  SELECT s.*
  FROM score_per_patient s, p90_val
  WHERE s.lab_instability_score >= p90_val.p90_score
),
lab_flags AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    MAX(IF(LOWER(label) LIKE '%creatinine%', 1, 0)) AS crit_cr,
    MAX(IF(LOWER(label) = 'potassium', 1, 0)) AS crit_k,
    MAX(IF(LOWER(label) LIKE '%platelet%', 1, 0)) AS crit_platelets,
    MAX(IF(LOWER(label) LIKE 'hemoglobin%', 1, 0)) AS crit_hgb,
    MAX(IF(LOWER(label) LIKE '%whole%potassium%', 1, 0)) AS crit_wholeblood_k,
    MAX(IF(LOWER(label) LIKE '%wbc%' OR LOWER(label) LIKE '%white blood%', 1, 0)) AS crit_wbc
  FROM labs_72h c
  GROUP BY c.subject_id, c.hadm_id
),
metrics_top AS (
  SELECT
    COUNT(*) AS n_top,
    AVG(hospital_expire_flag) AS mortality_rate,
    AVG(los_hosp) AS avg_los_days,
    AVG(crit_cr) AS rate_cr,
    AVG(crit_k) AS rate_k,
    AVG(crit_platelets) AS rate_platelets,
    AVG(crit_hgb) AS rate_hgb,
    AVG(crit_wholeblood_k) AS rate_wholeblood_k,
    AVG(crit_wbc) AS rate_wbc
  FROM top_tier t
  LEFT JOIN lab_flags lf
    ON t.subject_id = lf.subject_id AND t.hadm_id = lf.hadm_id
),
metrics_all AS (
  SELECT
    COUNT(*) AS n_all,
    AVG(CASE WHEN cohort.hospital_expire_flag IS NOT NULL THEN cohort.hospital_expire_flag ELSE 0 END) AS mortality_rate,
    AVG(cohort.los_hosp) AS avg_los_days,
    AVG(IFNULL(lf.crit_cr,0)) AS rate_cr,
    AVG(IFNULL(lf.crit_k,0)) AS rate_k,
    AVG(IFNULL(lf.crit_platelets,0)) AS rate_platelets,
    AVG(IFNULL(lf.crit_hgb,0)) AS rate_hgb,
    AVG(IFNULL(lf.crit_wholeblood_k,0)) AS rate_wholeblood_k,
    AVG(IFNULL(lf.crit_wbc,0)) AS rate_wbc
  FROM cohort
  LEFT JOIN lab_flags lf
    ON cohort.subject_id = lf.subject_id AND cohort.hadm_id = lf.hadm_id
)
SELECT
  m_top.*,
  m_all.rate_cr AS all_rate_cr,
  m_all.rate_k AS all_rate_k,
  m_all.rate_platelets AS all_rate_platelets,
  m_all.rate_hgb AS all_rate_hgb,
  m_all.rate_wholeblood_k AS all_rate_wholeblood_k,
  m_all.rate_wbc AS all_rate_wbc
FROM metrics_top m_top
CROSS JOIN metrics_all m_all;