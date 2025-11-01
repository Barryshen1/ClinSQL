WITH patient_cohort AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 51 AND 61
),
first_rr AS (
  SELECT pc.subject_id, MIN(ce.charttime) AS first_charttime
  FROM patient_cohort pc
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON pc.subject_id = icu.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON icu.stay_id = ce.stay_id
  WHERE ce.itemid = 220210  
  GROUP BY pc.subject_id
),
first_rr_value AS (
  SELECT fr.subject_id, ce.valuenum AS first_rr_value
  FROM first_rr fr
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON fr.subject_id = ce.subject_id AND fr.first_charttime = ce.charttime
  WHERE ce.itemid = 220210  
)

SELECT STDDEV(first_rr_value) AS sd_first_rr
FROM first_rr_value;