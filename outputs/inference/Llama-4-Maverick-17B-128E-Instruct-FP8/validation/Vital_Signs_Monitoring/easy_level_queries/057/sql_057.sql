WITH patient_filter AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 35 AND 45
),
icu_stays_filtered AS (
  SELECT icu.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN patient_filter p ON icu.subject_id = p.subject_id
),
respiratory_rate_max AS (
  SELECT ce.stay_id, MAX(ce.valuenum) AS max_rr
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN icu_stays_filtered icu ON ce.stay_id = icu.stay_id
  WHERE ce.itemid IN (220210, 615, 618, 220339)  
  GROUP BY ce.stay_id
)
SELECT MIN(max_rr) AS min_max_rr
FROM respiratory_rate_max;