WITH patient_cohort AS (
  SELECT 
    subject_id,
    anchor_year,
    anchor_age,
    gender
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 51 AND 61
),
icu_stays AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    CAST(p.anchor_year AS INT64) - p.anchor_age AS birth_year,
    TIMESTAMP_DIFF(i.intime, DATE(CAST(p.anchor_year AS INT64) - p.anchor_age, 1, 1), YEAR) AS age_at_icu,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN patient_cohort p ON i.subject_id = p.subject_id
),
first_icu_stays AS (
  SELECT 
    subject_id,
    hadm_id,
    stay_id,
    intime,
    outtime,
    birth_year,
    age_at_icu
  FROM icu_stays
  WHERE rn = 1
),
spo2_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE category = 'Pulse oximetry'
    AND label LIKE '%SpO2%'
),
spo2_data AS (
  SELECT 
    f.subject_id,
    f.stay_id,
    c.valuenum AS spo2_value
  FROM first_icu_stays f
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON f.subject_id = c.subject_id
    AND f.stay_id = c.stay_id
    AND c.charttime BETWEEN f.intime AND LEAST(TIMESTAMP_ADD(f.intime, INTERVAL 48 HOUR), f.outtime)
  WHERE c.itemid IN (SELECT itemid FROM spo2_itemids)
    AND c.valuenum IS NOT NULL
),
avg_spo2_per_stay AS (
  SELECT 
    subject_id,
    stay_id,
    AVG(spo2_value) AS avg_spo2
  FROM spo2_data
  GROUP BY subject_id, stay_id
),
spo2_categories AS (
  SELECT 
    subject_id,
    stay_id,
    avg_spo2,
    CASE 
      WHEN avg_spo2 < 90 THEN '<90'
      WHEN avg_spo2 BETWEEN 90 AND 92 THEN '90-92'
      WHEN avg_spo2 BETWEEN 93 AND 95 THEN '93-95'
      WHEN avg_spo2 > 95 THEN '>95'
      ELSE NULL 
    END AS spo2_category
  FROM avg_spo2_per_stay
),
aki_icd_codes AS (
  SELECT * FROM UNNEST([
    'R19.2', 'R19.3', 'R19.4', 'R19.5', 'R19.6', 'R19.7', 'R19.8', 'R19.9',
    'N17.0', 'N17.1', 'N17.2', 'N17.3', 'N17.4', 'N17.5', 'N17.6', 'N17.7', 'N17.8', 'N17.9',
    'N18.1', 'N18.2', 'N18.3', 'N18.4', 'N18.5', 'N18.6', 'N18.7', 'N18.8', 'N18.9',
    'N19.0', 'N19.1', 'N19.2', 'N19.3', 'N19.4', 'N19.5', 'N19.6', 'N19.7', 'N19.8', 'N19.9'
  ]) AS icd_code
),
aki_flags AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN aki_icd_codes a ON d.icd_code = a.icd_code
  WHERE d.icd_version = 10
    AND d.hadm_id IN (SELECT hadm_id FROM first_icu_stays)
),
final_data AS (
  SELECT 
    s.subject_id,
    s.stay_id,
    s.spo2_category,
    COALESCE(CASE WHEN a.subject_id IS NOT NULL THEN 1 ELSE 0 END, 0) AS aki_flag
  FROM spo2_categories s
  LEFT JOIN first_icu_stays f 
    ON s.subject_id = f.subject_id AND s.stay_id = f.stay_id
  LEFT JOIN aki_flags a 
    ON f.subject_id = a.subject_id AND f.hadm_id = a.hadm_id
)
SELECT 
  spo2_category,
  COUNT(DISTINCT subject_id) AS patient_count,
  SUM(aki_flag) * 1.0 / COUNT(DISTINCT subject_id) AS aki_rate
FROM final_data
GROUP BY spo2_category
ORDER BY 
  CASE spo2_category
    WHEN '<90' THEN 1
    WHEN '90-92' THEN 2
    WHEN '93-95' THEN 3
    WHEN '>95' THEN 4
  END;