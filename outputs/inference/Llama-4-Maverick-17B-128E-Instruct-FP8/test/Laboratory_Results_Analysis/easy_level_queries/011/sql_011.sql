WITH patient_filter AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age = 56
),
icu_stays AS (
  SELECT i.stay_id, i.subject_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN patient_filter p ON i.subject_id = p.subject_id
),
potassium_measurements AS (
  SELECT i.stay_id, MAX(c.valuenum) AS peak_potassium
  FROM icu_stays i
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c ON i.stay_id = c.stay_id
  WHERE c.itemid = 50822  
  GROUP BY i.stay_id
)
SELECT STDDEV(peak_potassium) AS std_dev_peak_potassium
FROM potassium_measurements;