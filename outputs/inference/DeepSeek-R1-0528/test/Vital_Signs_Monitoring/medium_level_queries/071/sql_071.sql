WITH cohort AS (
  SELECT 
    icu.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'F' 
    AND pat.anchor_age BETWEEN 38 AND 48
),
spo2_data AS (
  SELECT 
    ce.stay_id,
    ce.valuenum AS spo2
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  WHERE 
    ce.itemid IN (220277, 223835)  -- SpO2 item IDs
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 0 AND 100  -- Valid SpO2 range
),
per_stay_mean AS (
  SELECT 
    stay_id,
    AVG(spo2) AS mean_spo2
  FROM spo2_data
  GROUP BY stay_id
),
cohort_spo2 AS (
  SELECT 
    c.stay_id,
    psm.mean_spo2
  FROM cohort c
  INNER JOIN per_stay_mean psm
    ON c.stay_id = psm.stay_id
)
SELECT 
  -- Calculate proportion of stays with mean_spo2 <= 92 as a percentage
  (COUNTIF(mean_spo2 <= 92) / COUNT(*)) * 100 AS percentile
FROM cohort_spo2;