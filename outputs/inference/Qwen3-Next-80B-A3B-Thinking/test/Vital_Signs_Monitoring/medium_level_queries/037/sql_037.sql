WITH hfnc_patients AS (
  SELECT DISTINCT
    icustays.stay_id,
    icustays.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icustays
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` patients
    ON icustays.subject_id = patients.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.inputevents` inputevents
    ON icustays.stay_id = inputevents.stay_id
  WHERE patients.gender = 'F'
    AND patients.anchor_age BETWEEN 88 AND 98
    AND inputevents.itemid = 223835
)
SELECT
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY valuenum) AS median_gcs
FROM `physionet-data.mimiciv_3_1_icu.chartevents` chartevents
JOIN hfnc_patients
  ON chartevents.stay_id = hfnc_patients.stay_id
WHERE chartevents.itemid = 223900
  AND chartevents.charttime >= hfnc_patients.intime + INTERVAL '24 hours';