WITH
-- Get male patients aged 45-55 with heart failure
heart_failure_patients AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    AND (d.icd_code LIKE 'I50.%' OR di.long_title LIKE '%heart failure%')
),

-- Get ICU stays for these patients
icu_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    s.los,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN
    heart_failure_patients hf ON s.subject_id = hf.subject_id AND s.hadm_id = hf.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON s.subject_id = a.subject_id AND s.hadm_id = a.hadm_id
),

-- Get vital signs in first 72 hours of ICU stay
vital_signs AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.charttime,
    -- Heart rate (tachycardia >100)
    MAX(CASE WHEN c.itemid = 220045 THEN c.valuenum ELSE NULL END) AS heart_rate,
    -- MAP (hypotension <65)
    MAX(CASE WHEN c.itemid = 220050 THEN c.valuenum ELSE NULL END) AS map,
    -- Respiratory rate (tachypnea >20)
    MAX(CASE WHEN c.itemid = 220210 THEN c.valuenum ELSE NULL END) AS resp_rate
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN
    icu_stays s ON c.subject_id = s.subject_id AND c.hadm_id = s.hadm_id AND c.stay_id = s.stay_id
  WHERE
    c.charttime BETWEEN s.intime AND DATETIME_ADD(s.intime, INTERVAL 72 HOUR)
    AND c.itemid IN (220045, 220050, 220210)
  GROUP BY
    c.subject_id, c.hadm_id, c.stay_id, c.charttime
),

-- Calculate composite instability score for each time point
instability_scores AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    charttime,
    heart_rate,
    map,
    resp_rate,
    -- Composite score (sum of binary indicators for instability)
    (CASE WHEN heart_rate > 100 THEN 1 ELSE 0 END) +
    (CASE WHEN map < 65 THEN 1 ELSE 0 END) +
    (CASE WHEN resp_rate > 20 THEN 1 ELSE 0 END) AS instability_score
  FROM
    vital_signs
),

-- Get maximum instability score per patient in first 72h
max_scores AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    MAX(instability_score) AS max_instability_score
  FROM
    instability_scores
  GROUP BY
    subject_id, hadm_id, stay_id
),

-- Calculate 99th percentile of max instability scores
percentile_99 AS (
  SELECT
    PERCENTILE_CONT(max_instability_score, 0.99) OVER() AS p99
  FROM
    max_scores
  LIMIT 1
),

-- Identify most unstable quartile (top 25%)
most_unstable_quartile AS (
  SELECT
    m.subject_id,
    m.hadm_id,
    m.stay_id,
    m.max_instability_score,
    s.los,
    s.hospital_expire_flag,
    -- Calculate quartile threshold
    PERCENTILE_CONT(m.max_instability_score, 0.75) OVER() AS quartile_threshold
  FROM
    max_scores m
  JOIN
    icu_stays s ON m.subject_id = s.subject_id AND m.hadm_id = s.hadm_id AND m.stay_id = s.stay_id
),

-- Final comparison between most unstable quartile and all ICU patients
final_comparison AS (
  SELECT
    'Most Unstable Quartile' AS group_name,
    COUNT(*) AS patient_count,
    AVG(CASE WHEN heart_rate > 100 THEN 1 ELSE 0 END) AS avg_tachycardia,
    AVG(CASE WHEN map < 65 THEN 1 ELSE 0 END) AS avg_map_lt_65,
    AVG(CASE WHEN resp_rate > 20 THEN 1 ELSE 0 END) AS avg_tachypnea,
    AVG(los) AS avg_icu_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM
    most_unstable_quartile m
  JOIN
    instability_scores i ON m.subject_id = i.subject_id AND m.hadm_id = i.hadm_id AND m.stay_id = i.stay_id
  WHERE
    i.instability_score = m.max_instability_score
    AND m.max_instability_score >= m.quartile_threshold
  UNION ALL
  SELECT
    'All ICU Patients' AS group_name,
    COUNT(*) AS patient_count,
    AVG(CASE WHEN heart_rate > 100 THEN 1 ELSE 0 END) AS avg_tachycardia,
    AVG(CASE WHEN map < 65 THEN 1 ELSE 0 END) AS avg_map_lt_65,
    AVG(CASE WHEN resp_rate > 20 THEN 1 ELSE 0 END) AS avg_tachypnea,
    AVG(los) AS avg_icu_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM
    icu_stays s
  JOIN
    instability_scores i ON s.subject_id = i.subject_id AND s.hadm_id = i.hadm_id AND s.stay_id = i.stay_id
)

-- Final results
SELECT
  group_name,
  patient_count,
  avg_tachycardia,
  avg_map_lt_65,
  avg_tachypnea,
  avg_icu_los,
  mortality_rate
FROM
  final_comparison
ORDER BY
  group_name;