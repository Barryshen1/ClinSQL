WITH patient_birth AS (
  SELECT 
    subject_id,
    gender,  -- Added to include gender for filtering
    DATE_SUB(CAST(CONCAT(anchor_year, '-01-01') AS DATE), INTERVAL anchor_age YEAR) AS birth_date
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
),
icu_stays_with_age AS (
  SELECT 
    i.*,
    TIMESTAMP_DIFF(i.intime, p.birth_date, YEAR) AS age_at_icu
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN patient_birth p ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND TIMESTAMP_DIFF(i.intime, p.birth_date, YEAR) BETWEEN 89 AND 99
),
map_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label LIKE '%MAP%'
    AND category = 'Vital Signs'
    AND unitname = 'mmHg'
),
map_measurements AS (
  SELECT 
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN map_items m ON ce.itemid = m.itemid
  WHERE ce.valuenum IS NOT NULL
),
first_24h_map AS (
  SELECT 
    ms.stay_id,
    ms.valuenum
  FROM map_measurements ms
  JOIN icu_stays_with_age i ON ms.stay_id = i.stay_id
  WHERE ms.charttime BETWEEN i.intime AND DATETIME_ADD(i.intime, INTERVAL 24 HOUR)
),
avg_map_per_stay AS (
  SELECT 
    stay_id,
    AVG(valuenum) AS avg_map
  FROM first_24h_map
  GROUP BY stay_id
)
SELECT AVG(avg_map) AS overall_avg_map
FROM avg_map_per_stay;