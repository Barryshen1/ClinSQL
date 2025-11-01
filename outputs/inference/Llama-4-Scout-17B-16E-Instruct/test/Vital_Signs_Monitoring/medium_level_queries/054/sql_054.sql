WITH patient_info AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE 
    p.gender = 'F' AND p.anchor_age BETWEEN 87 AND 97
),
icu_stays AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN 
    patient_info p ON i.subject_id = p.subject_id
),
sbp_measurements AS (
  SELECT 
    ce.stay_id,
    ce.charttime,
    ce.valuenum AS sbp
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN 
    icu_stays i ON ce.stay_id = i.stay_id
  WHERE 
    ce.itemid = 220050  # SBP itemid
    AND ce.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 1 DAY)
),
avg_sbp_per_stay AS (
  SELECT 
    stay_id,
    AVG(sbp) AS avg_sbp
  FROM 
    sbp_measurements
  GROUP BY 
    stay_id
),
quantiles AS (
  SELECT 
    APPROX_QUANTILES(avg_sbp, 100) AS quantiles
  FROM 
    avg_sbp_per_stay
)
SELECT 
  (SELECT COUNTIF(q <= 150) / ARRAY_LENGTH(quantiles)) * 100
FROM 
  quantiles;