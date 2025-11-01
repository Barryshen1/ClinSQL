WITH patient_subset AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 63 AND 73
),
respiratory_rate_max AS (
  SELECT icu.stay_id, MAX(ce.valuenum) AS max_rr
  FROM patient_subset p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON p.subject_id = icu.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON icu.stay_id = ce.stay_id
  WHERE ce.itemid IN (220339, 224690)  
  AND ce.valuenum IS NOT NULL
  GROUP BY icu.stay_id
)
SELECT STDDEV(max_rr) AS sd_max_rr
FROM respiratory_rate_max;