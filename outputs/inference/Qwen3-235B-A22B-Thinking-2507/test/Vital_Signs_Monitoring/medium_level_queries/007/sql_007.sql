WITH filtered_stays AS (
  SELECT 
    ie.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM ie.intime) - p.anchor_year)) BETWEEN 80 AND 90
),
stay_avg_spo2 AS (
  SELECT 
    fs.stay_id,
    AVG(ce.valuenum) AS avg_spo2
  FROM filtered_stays fs
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON fs.stay_id = ce.stay_id
  WHERE 
    ce.itemid = 220277  -- Standard SpO2 itemid (pulse oximetry)
    AND ce.valuenum IS NOT NULL
  GROUP BY fs.stay_id
)
SELECT 
  (COUNTIF(avg_spo2 <= 88) * 100.0) / COUNT(*) AS percentile
FROM stay_avg_spo2;