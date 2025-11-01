WITH patient_data AS (
  SELECT p.subject_id, p.anchor_age, ie.stay_id, ie.intime, ie.outtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie ON p.subject_id = ie.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 85 AND 95
),
temp_data AS (
  SELECT pd.stay_id, AVG(ce.valuenum) AS avg_temp
  FROM patient_data pd
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON pd.stay_id = ce.stay_id
  WHERE ce.itemid = 223762  
  AND ce.charttime BETWEEN pd.intime AND pd.outtime
  GROUP BY pd.stay_id
)
SELECT COUNTIF(avg_temp <= 36.0) / COUNT(*) AS percentile_rank
FROM temp_data;