WITH 
-- Identify female patients aged 60-70
patients_eligible AS (
  SELECT subject_id, anchor_age, gender
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 60 AND 70
),

-- Identify ICU stays for eligible patients with mixed shock
icu_stays_eligible AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime, i.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN patients_eligible p ON i.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE d.icd_code LIKE 'R57%'  -- Mixed shock ICD code, adjust as necessary
),

-- Sample vital signs for MAP and heart rate within the first 48 hours of ICU stay
vital_signs AS (
  SELECT 
    ce.subject_id, 
    ce.hadm_id, 
    ce.stay_id, 
    ce.charttime,
    ce.valuenum AS map_valuenum,
    ce.value AS map_value
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN icu_stays_eligible ise ON ce.stay_id = ise.stay_id
  WHERE ce.itemid = 220050  -- MAP
  AND ce.charttime BETWEEN ise.intime AND TIMESTAMP_ADD(ise.intime, INTERVAL 48 HOUR)
),

heart_rate_vitals AS (
  SELECT 
    ce.subject_id, 
    ce.hadm_id, 
    ce.stay_id, 
    ce.charttime,
    ce.valuenum AS heart_rate_valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN icu_stays_eligible ise ON ce.stay_id = ise.stay_id
  WHERE ce.itemid = 220179  -- Heart rate
  AND ce.charttime BETWEEN ise.intime AND TIMESTAMP_ADD(ise.intime, INTERVAL 48 HOUR)
),

-- Calculate instability score (simple example, adjust as necessary)
instability_score AS (
  SELECT 
    subject_id,
    hadm_id,
    stay_id,
    -- Example instability score calculation
    PERCENT_RANK() OVER (PARTITION BY subject_id ORDER BY map_valuenum) AS instability_score
  FROM vital_signs
),

-- Calculate cohort 95th-percentile instability score
cohort_percentile AS (
  SELECT 
    APPROX_QUANTILES(instability_score, 0.95)[OFFSET(1)] AS percentile_score
  FROM instability_score
),

-- Identify top decile patients
top_decile_patients AS (
  SELECT subject_id, hadm_id, stay_id
  FROM instability_score
  WHERE instability_score > (SELECT percentile_score FROM cohort_percentile)
)

-- Compare outcomes for top decile vs. cohort
SELECT 
  'Hypotension (MAP<65)' AS outcome,
  COUNT(DISTINCT CASE WHEN map_valuenum < 65 THEN subject_id END) AS count_hypotension,
  COUNT(DISTINCT subject_id) AS total_patients
FROM vital_signs
UNION ALL
SELECT 
  'Tachycardia',
  COUNT(DISTINCT CASE WHEN heart_rate_valuenum > 100 THEN subject_id END),
  COUNT(DISTINCT subject_id)
FROM heart_rate_vitals
WHERE subject_id IN (SELECT subject_id FROM top_decile_patients)
UNION ALL
SELECT 
  'ICU LOS',
  AVG(TIMESTAMP_DIFF(outtime, intime, HOUR)) AS icu_los,
  COUNT(DISTINCT subject_id)
FROM icu_stays_eligible
UNION ALL
SELECT 
  'Mortality',
  COUNT(DISTINCT CASE WHEN a.hospital_expire_flag = 1 THEN subject_id END),
  COUNT(DISTINCT subject_id)
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN patients_eligible p ON a.subject_id = p.subject_id;