WITH patient_cohort AS (
  SELECT p.subject_id, p.anchor_age, ie.stay_id, ie.intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie ON p.subject_id = ie.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 87 AND 97
),
avg_sbp AS (
  SELECT pc.stay_id, AVG(ce.valuenum) AS avg_sbp
  FROM patient_cohort pc
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON pc.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE di.label LIKE '%Systolic Blood Pressure%' 
  AND ce.charttime BETWEEN pc.intime AND TIMESTAMP_ADD(pc.intime, INTERVAL 24 HOUR)
  GROUP BY pc.stay_id
)
SELECT COUNTIF(a.avg_sbp <= 150) / COUNT(*) AS percentile
FROM avg_sbp a;