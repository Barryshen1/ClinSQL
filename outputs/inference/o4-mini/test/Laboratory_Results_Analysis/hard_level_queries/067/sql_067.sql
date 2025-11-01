WITH
-- 1. ACS cohort admissions for 53–63 y/o females with an ACS diagnosis
acs_adms AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id
   AND a.hadm_id    = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code    = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
    AND LOWER(dd.long_title) LIKE '%acute coronary%'
),

-- 2. Compute 72-hour instability score for ACS
acs_scores AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    COUNT(DISTINCT li.category) AS instability_score
  FROM acs_adms a
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON a.subject_id = le.subject_id
   AND a.hadm_id    = le.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON le.itemid = li.itemid
  WHERE le.flag = 'abnormal'
    AND le.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
  GROUP BY a.subject_id, a.hadm_id
),

-- 3. Tie back LOS and expire flag, assign quartiles
acs_q AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.instability_score,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR)/24.0 AS los_days,
    NTILE(4) OVER (ORDER BY s.instability_score) AS quartile
  FROM acs_scores s
  JOIN acs_adms a
    ON s.subject_id = a.subject_id
   AND s.hadm_id    = a.hadm_id
),

-- 4. ACS summary by quartile
acs_summary AS (
  SELECT
    quartile,
    COUNT(*)                               AS n_patients,
    100.0 * SUM(hospital_expire_flag) / COUNT(*)   AS mortality_pct,
    AVG(los_days)                          AS avg_los_days,
    AVG(instability_score)                 AS avg_instability_score
  FROM acs_q
  GROUP BY quartile
  ORDER BY quartile
),

-- 5. Control cohort: same female 53–63 but without ACS
ctrl_adms AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
    AND (a.hadm_id NOT IN (SELECT hadm_id FROM acs_adms))
),

-- 6. Compute 72-hour instability score for controls
ctrl_scores AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    COUNT(DISTINCT li.category) AS instability_score
  FROM ctrl_adms c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.subject_id = le.subject_id
   AND c.hadm_id    = le.hadm_id
   AND le.flag      = 'abnormal'
   AND le.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON le.itemid = li.itemid
  GROUP BY c.subject_id, c.hadm_id
),

-- 7. Compute mean instability for ACS vs controls
comparison AS (
  SELECT 'ACS' AS cohort, AVG(instability_score) AS mean_instability_score
  FROM acs_scores
  UNION ALL
  SELECT 'Control' AS cohort, AVG(instability_score) AS mean_instability_score
  FROM ctrl_scores
)

-- Final output
SELECT
  'Quartile Summaries (ACS)' AS section, NULL AS quartile, NULL AS mortality_pct, NULL AS avg_los_days, NULL AS avg_instability_score
UNION ALL
SELECT
  CAST(quartile AS STRING), quartile, ROUND(mortality_pct,2), ROUND(avg_los_days,2), ROUND(avg_instability_score,2)
FROM acs_summary

UNION ALL

SELECT
  'Comparison: Mean Instability', NULL, NULL, NULL, NULL
UNION ALL
SELECT
  cohort, NULL, NULL, NULL, ROUND(mean_instability_score,2)
FROM comparison
;