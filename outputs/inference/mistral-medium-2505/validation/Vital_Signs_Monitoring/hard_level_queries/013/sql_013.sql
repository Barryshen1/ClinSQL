WITH
-- Get male patients aged 68-78
male_patients AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 68 AND 78
),

-- Get multi-trauma admissions (using ICD-9 codes for multiple trauma)
trauma_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    -- ICD-9 codes for multiple trauma (800-804, 805-809, 810-819, 820-829, 830-839, 840-848, 850-854, 860-869, 870-879, 880-897, 900-904, 910-919, 920-924, 925-929, 930-939, 940-949, 950-957, 958-959)
    (d.icd_code BETWEEN '800' AND '804' OR
     d.icd_code BETWEEN '805' AND '809' OR
     d.icd_code BETWEEN '810' AND '819' OR
     d.icd_code BETWEEN '820' AND '829' OR
     d.icd_code BETWEEN '830' AND '839' OR
     d.icd_code BETWEEN '840' AND '848' OR
     d.icd_code BETWEEN '850' AND '854' OR
     d.icd_code BETWEEN '860' AND '869' OR
     d.icd_code BETWEEN '870' AND '879' OR
     d.icd_code BETWEEN '880' AND '897' OR
     d.icd_code BETWEEN '900' AND '904' OR
     d.icd_code BETWEEN '910' AND '919' OR
     d.icd_code BETWEEN '920' AND '924' OR
     d.icd_code BETWEEN '925' AND '929' OR
     d.icd_code BETWEEN '930' AND '939' OR
     d.icd_code BETWEEN '940' AND '949' OR
     d.icd_code BETWEEN '950' AND '957' OR
     d.icd_code BETWEEN '958' AND '959')
),

-- Get first ICU stays for these patients
first_icu_stays AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime AS icu_intime,
    i.outtime AS icu_outtime,
    i.los AS icu_los,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id, i.hadm_id ORDER BY i.intime) AS icu_stay_rank
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    trauma_admissions a
    ON i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
  WHERE
    i.subject_id IN (SELECT subject_id FROM male_patients)
),

-- Get vital signs for first 24 hours of first ICU stay
vital_signs_24h AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    c.charttime,
    -- Heart rate (itemid 220045)
    MAX(CASE WHEN c.itemid = 220045 THEN c.valuenum ELSE NULL END) AS heart_rate,
    -- Systolic BP (itemid 220050)
    MAX(CASE WHEN c.itemid = 220050 THEN c.valuenum ELSE NULL END) AS systolic_bp,
    -- Diastolic BP (itemid 220051)
    MAX(CASE WHEN c.itemid = 220051 THEN c.valuenum ELSE NULL END) AS diastolic_bp,
    -- Respiratory rate (itemid 220210)
    MAX(CASE WHEN c.itemid = 220210 THEN c.valuenum ELSE NULL END) AS respiratory_rate
  FROM
    first_icu_stays f
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON f.subject_id = c.subject_id AND f.hadm_id = c.hadm_id AND f.stay_id = c.stay_id
  WHERE
    f.icu_stay_rank = 1
    AND c.charttime BETWEEN f.icu_intime AND DATETIME_ADD(f.icu_intime, INTERVAL 24 HOUR)
    AND c.itemid IN (220045, 220050, 220051, 220210)
  GROUP BY
    f.subject_id, f.hadm_id, f.stay_id, c.charttime
),

-- Calculate instability score for each patient (example formula)
instability_scores AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    -- Example instability score calculation (adjust as needed)
    AVG(
      (CASE WHEN heart_rate > 100 THEN 1 ELSE 0 END) +
      (CASE WHEN systolic_bp < 90 THEN 1 ELSE 0 END) +
      (CASE WHEN respiratory_rate > 20 THEN 1 ELSE 0 END)
    ) AS instability_score
  FROM
    vital_signs_24h
  GROUP BY
    subject_id, hadm_id, stay_id
),

-- Calculate top decile count
top_decile_count AS (
  SELECT CEIL(COUNT(*) * 0.1) AS count FROM instability_scores
),

-- Get quartiles of instability scores
quartiles AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    instability_score,
    NTILE(4) OVER (ORDER BY instability_score) AS quartile
  FROM
    instability_scores
),

-- Get top decile of instability scores
top_decile AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    instability_score
  FROM
    instability_scores
  ORDER BY
    instability_score DESC
  LIMIT
    (SELECT count FROM top_decile_count)
),

-- Count episodes in top decile
top_decile_episodes AS (
  SELECT
    t.subject_id,
    COUNT(DISTINCT CASE WHEN vs.heart_rate > 100 THEN vs.charttime END) AS tachycardia_count,
    COUNT(DISTINCT CASE WHEN vs.systolic_bp < 90 THEN vs.charttime END) AS hypotension_count,
    COUNT(DISTINCT CASE WHEN vs.respiratory_rate > 20 THEN vs.charttime END) AS tachypnea_count
  FROM
    top_decile t
  JOIN
    vital_signs_24h vs
    ON t.subject_id = vs.subject_id AND t.hadm_id = vs.hadm_id AND t.stay_id = vs.stay_id
  GROUP BY
    t.subject_id
)

-- Quartile analysis
SELECT
  'Quartile Analysis' AS analysis_type,
  CAST(q.quartile AS STRING) AS quartile,
  COUNT(*) AS patient_count,
  AVG(q.instability_score) AS mean_instability_score,
  AVG(f.icu_los) AS mean_icu_los,
  SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_count,
  ROUND(SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS mortality_percentage,
  NULL AS mean_tachycardia_episodes,
  NULL AS mean_hypotension_episodes,
  NULL AS mean_tachypnea_episodes
FROM
  quartiles q
JOIN
  first_icu_stays f ON q.subject_id = f.subject_id AND q.hadm_id = f.hadm_id AND q.stay_id = f.stay_id
JOIN
  trauma_admissions a ON q.subject_id = a.subject_id AND q.hadm_id = a.hadm_id
WHERE
  f.icu_stay_rank = 1
GROUP BY
  q.quartile

UNION ALL

-- Top decile analysis
SELECT
  'Top Decile Analysis' AS analysis_type,
  'Top Decile' AS quartile,
  COUNT(*) AS patient_count,
  AVG(t.instability_score) AS mean_instability_score,
  AVG(f.icu_los) AS mean_icu_los,
  SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_count,
  ROUND(SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS mortality_percentage,
  NULL AS mean_tachycardia_episodes,
  NULL AS mean_hypotension_episodes,
  NULL AS mean_tachypnea_episodes
FROM
  top_decile t
JOIN
  first_icu_stays f ON t.subject_id = f.subject_id AND t.hadm_id = f.hadm_id AND t.stay_id = f.stay_id
JOIN
  trauma_admissions a ON t.subject_id = a.subject_id AND t.hadm_id = a.hadm_id
WHERE
  f.icu_stay_rank = 1

UNION ALL

-- Episode counts
SELECT
  'Episode Counts' AS analysis_type,
  'Top Decile' AS quartile,
  NULL AS patient_count,
  NULL AS mean_instability_score,
  NULL AS mean_icu_los,
  NULL AS mortality_count,
  NULL AS mortality_percentage,
  AVG(tde.tachycardia_count) AS mean_tachycardia_episodes,
  AVG(tde.hypotension_count) AS mean_hypotension_episodes,
  AVG(tde.tachypnea_count) AS mean_tachypnea_episodes
FROM
  top_decile_episodes tde
ORDER BY
  analysis_type, quartile;