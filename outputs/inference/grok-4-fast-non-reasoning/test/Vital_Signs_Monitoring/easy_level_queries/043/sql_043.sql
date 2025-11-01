WITH eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 77 AND 87
),
first_icu_stays AS (
  SELECT icu.subject_id, icu.stay_id, icu.hadm_id, icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN eligible_patients pat ON icu.subject_id = pat.subject_id
  QUALIFY ROW_NUMBER() OVER (PARTITION BY icu.subject_id ORDER BY icu.intime) = 1
),
gcs_events AS (
  SELECT ce.subject_id, ce.stay_id, ce.charttime, ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN first_icu_stays fis ON ce.subject_id = fis.subject_id 
    AND ce.stay_id = fis.stay_id
    AND ce.itemid IN (220739, 223900, 223901)  -- GCS Total
    AND ce.charttime >= fis.intime
    AND ce.charttime <= fis.intime + INTERVAL 1 DAY
    AND ce.valuenum IS NOT NULL
),
first_gcs_per_stay AS (
  SELECT subject_id, stay_id, valuenum
  FROM gcs_events
  QUALIFY ROW_NUMBER() OVER (PARTITION BY stay_id ORDER BY charttime) = 1
)
SELECT AVG(valuenum) AS avg_first_gcs_total
FROM first_gcs_per_stay;