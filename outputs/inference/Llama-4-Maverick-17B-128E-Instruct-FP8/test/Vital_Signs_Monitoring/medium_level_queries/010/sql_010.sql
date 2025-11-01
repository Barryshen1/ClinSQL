WITH patient_data AS (
  SELECT p.subject_id, p.gender, icu.stay_id, icu.intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON p.subject_id = icu.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 77 AND 87
),
avg_sbp AS (
  SELECT pd.stay_id, AVG(ce.valuenum) AS avg_sbp
  FROM patient_data pd
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON pd.stay_id = ce.stay_id
  WHERE ce.itemid = 220050  
  AND ce.charttime BETWEEN pd.intime AND TIMESTAMP_ADD(pd.intime, INTERVAL 48 HOUR)
  GROUP BY pd.stay_id
)
SELECT COUNTIF(a.avg_sbp <= 160) / COUNT(*) AS percentile
FROM avg_sbp a;