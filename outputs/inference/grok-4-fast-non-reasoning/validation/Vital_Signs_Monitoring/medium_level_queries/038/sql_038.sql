WITH eligible_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 66 AND 76
    AND (i.first_careunit LIKE '%SICU%' 
         OR i.first_careunit LIKE '%MICU%' 
         OR i.first_careunit LIKE '%CCU%'
         OR i.last_careunit LIKE '%SICU%' 
         OR i.last_careunit LIKE '%MICU%' 
         OR i.last_careunit LIKE '%CCU%')
),
sbp_measurements AS (
  SELECT c.subject_id, c.stay_id, c.charttime, c.valuenum AS sbp
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  INNER JOIN eligible_patients ep ON c.subject_id = ep.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON c.subject_id = i.subject_id 
    AND c.hadm_id = i.hadm_id 
    AND c.stay_id = i.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON c.itemid = di.itemid
  WHERE di.label LIKE '%systolic%'
    AND c.charttime >= i.intime
    AND c.charttime <= TIMESTAMP_ADD(i.intime, INTERVAL 6 HOUR)
    AND c.valuenum IS NOT NULL
    AND c.valuenum > 0
    AND c.valuenum < 300
)
SELECT
  q1,
  q3,
  q3 - q1 AS iqr
FROM (
  SELECT
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY sbp) AS q1,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY sbp) AS q3
  FROM sbp_measurements
) percentiles
LIMIT 1;