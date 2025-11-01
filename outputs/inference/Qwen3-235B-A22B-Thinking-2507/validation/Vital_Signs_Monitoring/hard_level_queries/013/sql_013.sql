WITH first_icu AS (
  SELECT 
    *,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
trauma_counts AS (
  SELECT 
    hadm_id,
    COUNT(DISTINCT icd_code) AS trauma_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_version = 10 
    AND icd_code >= 'S00' AND icd_code <= 'T75'
  GROUP BY hadm_id
  HAVING COUNT(DISTINCT icd_code) >= 2
),
vital_signs_24h AS (
  SELECT
    ce.stay_id,
    SUM(CASE WHEN ce.itemid = 220045 AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS count_tachycardia,
    SUM(CASE WHEN ce.itemid IN (220050, 220179) AND ce.valuenum < 90 THEN 1 ELSE 0 END) AS count_hypotension,
    SUM(CASE WHEN ce.itemid = 220210 AND ce.valuenum > 20 THEN 1 ELSE 0 END) AS count_tachypnea
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN first_icu i 
    ON ce.stay_id = i.stay_id
  WHERE i.rn = 1
    AND ce.charttime >= i.intime 
    AND ce.charttime < DATETIME_ADD(i.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
  GROUP BY ce.stay_id
),
cohort AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.los,
    a.hospital_expire_flag,
    COALESCE(vs.count_tachycardia, 0) AS count_tachycardia,
    COALESCE(vs.count_hypotension, 0) AS count_hypotension,
    COALESCE(vs.count_tachypnea, 0) AS count_tachypnea,
    (COALESCE(vs.count_tachycardia, 0) + COALESCE(vs.count_hypotension, 0) + COALESCE(vs.count_tachypnea, 0)) AS instability_score,
    EXTRACT(YEAR FROM i.intime) - (p.anchor_year - p.anchor_age) AS age
  FROM first_icu i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  INNER JOIN trauma_counts tc
    ON i.hadm_id = tc.hadm_id
  LEFT JOIN vital_signs_24h vs
    ON i.stay_id = vs.stay_id
  WHERE i.rn = 1
    AND p.gender = 'M'
    AND EXTRACT(YEAR FROM i.intime) - (p.anchor_year - p.anchor_age) BETWEEN 68 AND 78
),
quartile_decile AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY instability_score) AS quartile,
    NTILE(10) OVER (ORDER BY instability_score) AS decile
  FROM cohort
)
SELECT 
  'quartile' AS report_type,
  quartile,
  COUNT(*) AS count,
  AVG(instability_score) AS mean_score,
  AVG(los) AS mean_los,
  AVG(hospital_expire_flag) AS mortality,
  CAST(NULL AS FLOAT64) AS mean_tachycardia,
  CAST(NULL AS FLOAT64) AS mean_hypotension,
  CAST(NULL AS FLOAT64) AS mean_tachypnea
FROM quartile_decile
GROUP BY quartile
UNION ALL
SELECT 
  'top_decile' AS report_type,
  CAST(NULL AS INT64) AS quartile,
  CAST(NULL AS INT64) AS count,
  CAST(NULL AS FLOAT64) AS mean_score,
  CAST(NULL AS FLOAT64) AS mean_los,
  CAST(NULL AS FLOAT64) AS mortality,
  AVG(count_tachycardia) AS mean_tachycardia,
  AVG(count_hypotension) AS mean_hypotension,
  AVG(count_tachypnea) AS mean_tachypnea
FROM quartile_decile
WHERE decile = 10;