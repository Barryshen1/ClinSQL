WITH patient_icu_stays AS (
  SELECT p.subject_id, i.stay_id, i.intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON p.subject_id = i.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 75 AND 85
),
systolic_bp AS (
  SELECT pis.stay_id, AVG(ce.valuenum) AS mean_sbp
  FROM patient_icu_stays pis
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON pis.stay_id = ce.stay_id
  WHERE ce.itemid = 220050  
  AND ce.charttime BETWEEN pis.intime AND TIMESTAMP_ADD(pis.intime, INTERVAL 48 HOUR)
  GROUP BY pis.stay_id
)
SELECT PERCENT_RANK() OVER (ORDER BY mean_sbp) AS percentile
FROM systolic_bp
WHERE mean_sbp <= 140
ORDER BY percentile DESC
LIMIT 1;