WITH ap_hadm AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE ((icd_version = 9 AND icd_code LIKE '577.0%')
         OR (icd_version = 10 AND icd_code LIKE 'K85%'))
),
cohort AS (
  SELECT 
    a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag,
    p.gender, p.anchor_age,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN ap_hadm aph ON a.subject_id = aph.subject_id AND a.hadm_id = aph.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 35 AND 45
    AND a.dischtime IS NOT NULL
),
diagnoses_count AS (
  SELECT 
    c.*,
    COUNT(di.icd_code) AS num_diagnoses
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
    ON c.subject_id = di.subject_id AND c.hadm_id = di.hadm_id
  GROUP BY 
    c.subject_id, c.hadm_id, c.admittime, c.dischtime, c.hospital_expire_flag,
    c.gender, c.anchor_age, c.los_days
),
major_comps AS (
  SELECT 
    subject_id, hadm_id,
    MAX(CASE WHEN (
      (icd_version = 9 AND (icd_code LIKE '038%' OR icd_code LIKE '995.91' OR icd_code LIKE '785.5%')) OR
      (icd_version = 10 AND (icd_code LIKE 'A40%' OR icd_code LIKE 'A41%' OR icd_code LIKE 'R65.2%'))
    ) THEN 1 ELSE 0 END) AS flag_sepsis,
    MAX(CASE WHEN (
      (icd_version = 9 AND icd_code LIKE '584%') OR
      (icd_version = 10 AND icd_code LIKE 'N17%')
    ) THEN 1 ELSE 0 END) AS flag_aki,
    MAX(CASE WHEN (
      (icd_version = 9 AND (icd_code LIKE '518.8%' OR icd_code = '799.1')) OR
      (icd_version = 10 AND (icd_code LIKE 'J96.0%' OR icd_code LIKE 'J96.2%'))
    ) THEN 1 ELSE 0 END) AS flag_resp,
    MAX(CASE WHEN (
      (icd_version = 9 AND icd_code LIKE '785.5%') OR
      (icd_version = 10 AND icd_code LIKE 'R57%')
    ) THEN 1 ELSE 0 END) AS flag_shock
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY subject_id, hadm_id
),
risk_scores AS (
  SELECT 
    dc.*,
    COALESCE(mc.flag_sepsis, 0) AS flag_sepsis,
    COALESCE(mc.flag_aki, 0) AS flag_aki,
    COALESCE(mc.flag_resp, 0) AS flag_resp,
    COALESCE(mc.flag_shock, 0) AS flag_shock,
    dc.num_diagnoses + 5 * (COALESCE(mc.flag_sepsis, 0) + COALESCE(mc.flag_aki, 0) + 
                            COALESCE(mc.flag_resp, 0) + COALESCE(mc.flag_shock, 0)) AS risk_score
  FROM diagnoses_count dc
  LEFT JOIN major_comps mc 
    ON dc.subject_id = mc.subject_id AND dc.hadm_id = mc.hadm_id
),
with_quartile AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY risk_score) AS quartile
  FROM risk_scores
),
metrics AS (
  SELECT 
    *,
    (COALESCE(flag_sepsis, 0) + COALESCE(flag_aki, 0) + COALESCE(flag_resp, 0) + COALESCE(flag_shock, 0)) AS total_flags,
    CASE WHEN hospital_expire_flag = 0 THEN los_days ELSE NULL END AS survivor_los
  FROM with_quartile
)
SELECT 
  'Overall' AS group_label,
  COUNT(*) AS num_patients,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_rate_pct,
  ROUND(100.0 * SUM(CASE WHEN total_flags > 0 THEN 1 ELSE 0 END) / COUNT(*), 2) AS major_complication_rate_pct,
  APPROX_QUANTILES(survivor_los, 2)[SAFE_OFFSET(1)] AS median_survivor_los_days
FROM metrics

UNION ALL

SELECT 
  CAST(quartile AS STRING) AS group_label,
  COUNT(*) AS num_patients,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_rate_pct,
  ROUND(100.0 * SUM(CASE WHEN total_flags > 0 THEN 1 ELSE 0 END) / COUNT(*), 2) AS major_complication_rate_pct,
  APPROX_QUANTILES(survivor_los, 2)[SAFE_OFFSET(1)] AS median_survivor_los_days
FROM metrics
GROUP BY quartile
ORDER BY CASE WHEN group_label = 'Overall' THEN 0 ELSE CAST(group_label AS INT64) END;