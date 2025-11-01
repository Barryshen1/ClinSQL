WITH patient_cohort AS (
  SELECT p.subject_id, i.stay_id, p.anchor_age, i.intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON p.subject_id = i.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 58 AND 68
),
map_measurements AS (
  SELECT patient_cohort.stay_id, c.valuenum
  FROM patient_cohort
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c ON patient_cohort.stay_id = c.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` d ON c.itemid = d.itemid
  WHERE d.label LIKE '%Mean Arterial Pressure%' AND c.charttime BETWEEN patient_cohort.intime AND TIMESTAMP_ADD(patient_cohort.intime, INTERVAL 48 HOUR)
),
mean_map AS (
  SELECT stay_id, AVG(valuenum) AS mean_map_value
  FROM map_measurements
  GROUP BY stay_id
)
SELECT SAFE_DIVIDE(COUNTIF(mean_map_value <= 85), COUNT(*)) AS percentile
FROM mean_map;