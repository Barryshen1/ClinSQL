WITH patients_filtered AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 38 AND 48
),
icustays_filtered AS (
  SELECT ie.subject_id, ie.stay_id, ie.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN patients_filtered p ON ie.subject_id = p.subject_id
),
respiratory_rate AS (
  SELECT ie.subject_id, ie.stay_id, ce.valuenum, ce.charttime
  FROM icustays_filtered ie
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON ie.stay_id = ce.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE di.label = 'Respiratory Rate' AND ce.charttime BETWEEN ie.intime AND TIMESTAMP_ADD(ie.intime, INTERVAL 24 HOUR)
)
SELECT subject_id, MAX(valuenum) AS max_respiratory_rate
FROM respiratory_rate
GROUP BY subject_id;