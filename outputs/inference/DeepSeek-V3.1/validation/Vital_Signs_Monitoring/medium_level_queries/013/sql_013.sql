WITH cohort AS (
  SELECT 
    ie.subject_id, 
    ie.hadm_id, 
    ie.stay_id, 
    ie.intime,
    DATETIME_ADD(ie.intime, INTERVAL 48 HOUR) AS intime_48hr
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
),
spo2_data AS (
  SELECT 
    c.stay_id,
    AVG(ce.valuenum) AS avg_spo2
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.subject_id = ce.subject_id
      AND c.hadm_id = ce.hadm_id
      AND c.stay_id = ce.stay_id
      AND ce.charttime >= c.intime
      AND ce.charttime <= c.intime_48hr
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE di.label = 'SpO2'
    AND ce.valuenum IS NOT NULL
  GROUP BY c.stay_id
),
aki_diagnosis AS (
  SELECT 
    c.stay_id,
    MAX(CASE WHEN (dicd.icd_code LIKE '584%' AND dicd.icd_version = 9) 
               OR (dicd.icd_code LIKE 'N17%' AND dicd.icd_version = 10) 
             THEN 1 ELSE 0 END) AS aki_flag
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dicd
    ON c.hadm_id = dicd.hadm_id
  GROUP BY c.stay_id
),
categorized_spo2 AS (
  SELECT 
    sd.stay_id,
    sd.avg_spo2,
    ad.aki_flag,
    CASE 
      WHEN sd.avg_spo2 < 90 THEN '<90'
      WHEN sd.avg_spo2 BETWEEN 90 AND 92 THEN '90-92'
      WHEN sd.avg_spo2 BETWEEN 93 AND 95 THEN '93-95'
      ELSE '>95'
    END AS spo2_category
  FROM spo2_data sd
  INNER JOIN cohort c ON sd.stay_id = c.stay_id
  INNER JOIN aki_diagnosis ad ON sd.stay_id = ad.stay_id
)
SELECT 
  spo2_category,
  COUNT(DISTINCT cs.stay_id) AS stay_count,
  COUNT(DISTINCT c.subject_id) AS patient_count,
  ROUND(100.0 * SUM(aki_flag) / COUNT(*), 2) AS aki_rate_percent
FROM categorized_spo2 cs
INNER JOIN cohort c ON cs.stay_id = c.stay_id
GROUP BY spo2_category
ORDER BY spo2_category;