WITH
-- Get SpO2 itemid from d_items (assuming SpO2 is labeled as such)
spo2_item AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label = 'SpO2'
),

-- Get male ICU patients aged 73-83
male_patients_73_83 AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
),

-- Get ICU stays for these patients
icu_stays AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN male_patients_73_83 p ON i.subject_id = p.subject_id
),

-- Get SpO2 measurements in the first 24 hours of ICU stay
spo2_measurements AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.charttime,
    c.valuenum AS spo2_value
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN spo2_item s ON c.itemid = s.itemid
  JOIN icu_stays i ON c.subject_id = i.subject_id AND c.hadm_id = i.hadm_id AND c.stay_id = i.stay_id
  WHERE c.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR)
),

-- Calculate mean SpO2 for each ICU stay
mean_spo2 AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    AVG(spo2_value) AS mean_spo2
  FROM spo2_measurements
  GROUP BY subject_id, hadm_id, stay_id
  HAVING COUNT(spo2_value) > 0  -- Ensure at least one measurement
)

-- Calculate percentile rank for mean SpO2 = 92
SELECT
  PERCENT_RANK() OVER (ORDER BY mean_spo2) * 100 AS percentile_for_92_spo2
FROM mean_spo2
WHERE mean_spo2 <= 92
ORDER BY mean_spo2 DESC
LIMIT 1;