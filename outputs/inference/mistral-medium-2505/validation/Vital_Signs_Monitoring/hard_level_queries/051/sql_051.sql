WITH
-- Get male patients aged 89-99
male_patients AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    anchor_year,
    EXTRACT(YEAR FROM CURRENT_DATE()) - anchor_year + anchor_age AS current_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND (EXTRACT(YEAR FROM CURRENT_DATE()) - anchor_year + anchor_age) BETWEEN 89 AND 99
),

-- Get their ICU stays
icu_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime AS icu_intime,
    s.outtime AS icu_outtime,
    TIMESTAMP_DIFF(s.outtime, s.intime, HOUR) AS icu_los_hours,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    s.hadm_id = a.hadm_id
  JOIN
    male_patients p
  ON
    s.subject_id = p.subject_id
  WHERE
    s.intime IS NOT NULL
    AND s.outtime IS NOT NULL
),

-- Identify ischemic stroke patients
ischemic_stroke_patients AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
  ON
    d.icd_code = di.icd_code
    AND d.icd_version = di.icd_version
  WHERE
    d.icd_code LIKE 'I63.%'
    AND di.long_title LIKE '%ischemic stroke%'
),

-- Calculate instability score components (simplified example)
instability_components AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    -- Count of abnormal vital signs in first 48 hours
    COUNT(DISTINCT CASE WHEN ce.itemid IN (220045, 220046, 220047, 220048, 220049) THEN ce.charttime END) AS abnormal_vitals,
    -- Count of abnormal lab values in first 48 hours
    COUNT(DISTINCT CASE WHEN le.itemid IN (50885, 50886, 50887, 50888, 50889) THEN le.charttime END) AS abnormal_labs,
    -- Count of medication changes in first 48 hours
    COUNT(DISTINCT CASE WHEN p.starttime BETWEEN s.icu_intime AND TIMESTAMP_ADD(s.icu_intime, INTERVAL 48 HOUR) THEN p.pharmacy_id END) AS med_changes
  FROM
    icu_stays s
  LEFT JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON
    s.stay_id = ce.stay_id
    AND ce.charttime BETWEEN s.icu_intime AND TIMESTAMP_ADD(s.icu_intime, INTERVAL 48 HOUR)
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  ON
    s.subject_id = le.subject_id
    AND s.hadm_id = le.hadm_id
    AND le.charttime BETWEEN s.icu_intime AND TIMESTAMP_ADD(s.icu_intime, INTERVAL 48 HOUR)
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  ON
    s.subject_id = p.subject_id
    AND s.hadm_id = p.hadm_id
    AND p.starttime BETWEEN s.icu_intime AND TIMESTAMP_ADD(s.icu_intime, INTERVAL 48 HOUR)
  GROUP BY
    s.subject_id, s.hadm_id, s.stay_id
),

-- Calculate composite instability score
instability_scores AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.abnormal_vitals,
    i.abnormal_labs,
    i.med_changes,
    -- Simple composite score (weighted sum)
    (i.abnormal_vitals * 0.4 + i.abnormal_labs * 0.3 + i.med_changes * 0.3) AS instability_score,
    CASE WHEN isp.subject_id IS NOT NULL THEN 1 ELSE 0 END AS is_ischemic_stroke
  FROM
    instability_components i
  LEFT JOIN
    ischemic_stroke_patients isp
  ON
    i.subject_id = isp.subject_id
    AND i.hadm_id = isp.hadm_id
),

-- Get 95th percentile instability score for ischemic stroke patients
percentile_95 AS (
  SELECT
    APPROX_QUANTILES(instability_score, 100)[OFFSET(95)] AS p95_instability
  FROM
    instability_scores
  WHERE
    is_ischemic_stroke = 1
),

-- Identify top quartile of instability scores
top_quartile AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.instability_score,
    s.is_ischemic_stroke,
    i.icu_los_hours,
    i.hospital_expire_flag
  FROM
    instability_scores s
  JOIN
    icu_stays i
  ON
    s.subject_id = i.subject_id
    AND s.hadm_id = i.hadm_id
    AND s.stay_id = i.stay_id
  CROSS JOIN
    percentile_95 p
  WHERE
    s.instability_score >= p.p95_instability
)

-- Final comparison between ischemic stroke and general ICU in top quartile
SELECT
  is_ischemic_stroke AS patient_group,
  COUNT(*) AS n,
  AVG(instability_score) AS mean_instability,
  AVG(abnormal_vitals + abnormal_labs + med_changes) AS mean_abnormal_episodes,
  AVG(icu_los_hours) AS mean_icu_los_hours,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS mortality_rate
FROM
  top_quartile t
LEFT JOIN
  instability_components i
ON
  t.subject_id = i.subject_id
  AND t.hadm_id = i.hadm_id
  AND t.stay_id = i.stay_id
GROUP BY
  is_ischemic_stroke
ORDER BY
  is_ischemic_stroke DESC;