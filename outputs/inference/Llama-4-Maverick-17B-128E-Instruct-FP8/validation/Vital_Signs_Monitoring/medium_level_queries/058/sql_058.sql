WITH eligible_patients AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 38 AND 48
),
icu_stays AS (
  SELECT i.stay_id, i.subject_id, i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN eligible_patients p ON i.subject_id = p.subject_id
),
avg_sbp AS (
  SELECT i.stay_id, AVG(c.valuenum) AS avg_sbp
  FROM icu_stays i
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c ON i.stay_id = c.stay_id
  WHERE c.itemid = 220050  
  AND c.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR)
  GROUP BY i.stay_id
)
SELECT COUNTIF(avg_sbp.avg_sbp <= 120) * 100.0 / COUNT(*) AS percentile
FROM avg_sbp;