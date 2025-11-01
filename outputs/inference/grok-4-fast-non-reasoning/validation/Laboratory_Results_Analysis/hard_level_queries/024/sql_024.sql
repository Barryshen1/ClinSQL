WITH cohort AS (
  -- Define post-arrest cohort: females 53-63 with cardiac arrest diagnosis
  SELECT DISTINCT a.hadm_id, a.subject_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id 
    AND CAST(a.hadm_id AS STRING) = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
    AND (
      -- ICD-10 cardiac arrest
      (d.icd_version = '10' AND d.icd_code LIKE 'I46%') OR
      -- ICD-9 cardiac arrest
      (d.icd_version = '9' AND d.icd_code = '427.5')
    )
),

lab_scores AS (
  -- Compute instability score per admission (sum of abnormal labs in first 48h)
  SELECT 
    c.hadm_id,
    c.subject_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    -- Creatinine >2.0
    MAX(CASE WHEN le.itemid IN (50912, 50902) AND le.valuenum > 2.0 THEN 1 ELSE 0 END) AS abnormal_creatinine,
    -- BUN >40
    MAX(CASE WHEN le.itemid = 51006 AND le.valuenum > 40 THEN 1 ELSE 0 END) AS abnormal_bun,
    -- Sodium <130 or >150
    MAX(CASE WHEN le.itemid = 50824 AND (le.valuenum < 130 OR le.valuenum > 150) THEN 1 ELSE 0 END) AS abnormal_sodium,
    -- Potassium <3.0 or >6.0
    MAX(CASE WHEN le.itemid = 50971 AND (le.valuenum < 3.0 OR le.valuenum > 6.0) THEN 1 ELSE 0 END) AS abnormal_potassium,
    -- Glucose <70 or >300
    MAX(CASE WHEN le.itemid = 50931 AND (le.valuenum < 70 OR le.valuenum > 300) THEN 1 ELSE 0 END) AS abnormal_glucose,
    -- WBC <3.0 or >20.0
    MAX(CASE WHEN le.itemid = 51301 AND (le.valuenum < 3.0 OR le.valuenum > 20.0) THEN 1 ELSE 0 END) AS abnormal_wbc,
    -- ALT >200
    MAX(CASE WHEN le.itemid = 50878 AND le.valuenum > 200 THEN 1 ELSE 0 END) AS abnormal_alt,
    -- Troponin >0.5
    MAX(CASE WHEN le.itemid = 51237 AND le.valuenum > 0.5 THEN 1 ELSE 0 END) AS abnormal_troponin
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.subject_id = le.subject_id 
    AND CAST(c.hadm_id AS STRING) = le.hadm_id
    AND le.charttime >= c.admittime 
    AND le.charttime <= c.admittime + INTERVAL 48 HOUR
    AND le.valuenum IS NOT NULL
  GROUP BY c.hadm_id, c.subject_id, c.admittime, c.dischtime, c.hospital_expire_flag
),

scored_cohort AS (
  SELECT 
    *,
    (COALESCE(abnormal_creatinine, 0) + COALESCE(abnormal_bun, 0) + COALESCE(abnormal_sodium, 0) + 
     COALESCE(abnormal_potassium, 0) + COALESCE(abnormal_glucose, 0) + COALESCE(abnormal_wbc, 0) + 
     COALESCE(abnormal_alt, 0) + COALESCE(abnormal_troponin, 0)) AS instability_score
  FROM lab_scores
),

threshold AS (
  SELECT PERCENTILE_CONT(0.9, score) OVER() AS p90_score
  FROM (SELECT instability_score AS score FROM scored_cohort)
),

all_inpatients_critical AS (
  -- Comparison: % with >=1 critical lab in all female inpatients 53-63 (first 48h)
  WITH all_inpatients AS (
    SELECT DISTINCT a.hadm_id, a.subject_id, a.admittime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
    WHERE p.gender = 'F' AND p.anchor_age BETWEEN 53 AND 63
  ),
  all_labs AS (
    SELECT ai.hadm_id, ai.subject_id, ai.admittime,
      MAX(CASE WHEN le.itemid IN (50912, 50902) AND le.valuenum > 2.0 THEN 1 ELSE 0 END) AS abnormal_creatinine,
      MAX(CASE WHEN le.itemid = 51006 AND le.valuenum > 40 THEN 1 ELSE 0 END) AS abnormal_bun,
      MAX(CASE WHEN le.itemid = 50824 AND (le.valuenum < 130 OR le.valuenum > 150) THEN 1 ELSE 0 END) AS abnormal_sodium,
      MAX(CASE WHEN le.itemid = 50971 AND (le.valuenum < 3.0 OR le.valuenum > 6.0) THEN 1 ELSE 0 END) AS abnormal_potassium,
      MAX(CASE WHEN le.itemid = 50931 AND (le.valuenum < 70 OR le.valuenum > 300) THEN 1 ELSE 0 END) AS abnormal_glucose,
      MAX(CASE WHEN le.itemid = 51301 AND (le.valuenum < 3.0 OR le.valuenum > 20.0) THEN 1 ELSE 0 END) AS abnormal_wbc,
      MAX(CASE WHEN le.itemid = 50878 AND le.valuenum > 200 THEN 1 ELSE 0 END) AS abnormal_alt,
      MAX(CASE WHEN le.itemid = 51237 AND le.valuenum > 0.5 THEN 1 ELSE 0 END) AS abnormal_troponin
    FROM all_inpatients ai
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON ai.subject_id = le.subject_id AND CAST(ai.hadm_id AS STRING) = le.hadm_id
      AND le.charttime >= ai.admittime AND le.charttime <= ai.admittime + INTERVAL 48 HOUR
      AND le.valuenum IS NOT NULL
    GROUP BY ai.hadm_id, ai.subject_id, ai.admittime
  )
  SELECT 
    COUNT(*) AS total_all_inpatients,
    COUNT(CASE WHEN (COALESCE(abnormal_creatinine, 0) + COALESCE(abnormal_bun, 0) + COALESCE(abnormal_sodium, 0) + COALESCE(abnormal_potassium, 0) + COALESCE(abnormal_glucose, 0) + COALESCE(abnormal_wbc, 0) + COALESCE(abnormal_alt, 0) + COALESCE(abnormal_troponin, 0)) >= 1 THEN 1 END) AS critical_count_all,
    SAFE_DIVIDE(COUNT(CASE WHEN (COALESCE(abnormal_creatinine, 0) + COALESCE(abnormal_bun, 0) + COALESCE(abnormal_sodium, 0) + COALESCE(abnormal_potassium, 0) + COALESCE(abnormal_glucose, 0) + COALESCE(abnormal_wbc, 0) + COALESCE(abnormal_alt, 0) + COALESCE(abnormal_troponin, 0)) >= 1 THEN 1 END), COUNT(*)) AS pct_critical_all
  FROM all_labs
)

SELECT 
  t.p90_score AS percentile_90_instability_score,
  COUNT(sc.hadm_id) AS high_score_count,
  AVG(sc.hospital_expire_flag) AS mean_mortality,
  AVG(TIMESTAMPDIFF(DAY, sc.admittime, sc.dischtime)) AS mean_los_days,
  -- High-score critical lab frequency
  SAFE_DIVIDE(
    COUNT(CASE WHEN (COALESCE(sc.abnormal_creatinine, 0) + COALESCE(sc.abnormal_bun, 0) + COALESCE(sc.abnormal_sodium, 0) + COALESCE(sc.abnormal_potassium, 0) + COALESCE(sc.abnormal_glucose, 0) + COALESCE(sc.abnormal_wbc, 0) + COALESCE(sc.abnormal_alt, 0) + COALESCE(sc.abnormal_troponin, 0)) >= 1 THEN 1 END), 
    COUNT(sc.hadm_id)
  ) AS pct_critical_high_score,
  -- Comparison to all inpatients
  aic.pct_critical_all AS pct_critical_all_inpatients
FROM scored_cohort sc
CROSS JOIN threshold t
CROSS JOIN all_inpatients_critical aic
WHERE sc.instability_score >= t.p90_score
GROUP BY t.p90_score, aic.pct_critical_all;