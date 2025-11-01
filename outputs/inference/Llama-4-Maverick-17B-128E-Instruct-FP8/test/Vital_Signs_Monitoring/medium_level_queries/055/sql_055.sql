WITH patient_stays AS (
  SELECT i.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 87 AND 97
),
stay_avg_spo2 AS (
  SELECT i.stay_id, AVG(c.valuenum) AS avg_spo2
  FROM patient_stays ps
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON ps.stay_id = i.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c ON i.stay_id = c.stay_id
  WHERE c.itemid = 220277 AND c.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR)
  GROUP BY i.stay_id
)
SELECT COUNTIF(avg_spo2 <= 88) / COUNT(*) AS percentile
FROM stay_avg_spo2;