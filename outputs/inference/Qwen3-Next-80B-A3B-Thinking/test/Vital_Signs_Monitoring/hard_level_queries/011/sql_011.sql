WITH pneumonia_patients AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code BETWEEN '480' AND '486')
    OR (icd_version = 10 AND icd_code BETWEEN 'J12' AND 'J18')
),

eligible_patients AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.anchor_year,
    a.admittime,
    i.stay_id,
    i.intime,
    i.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
  WHERE 
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 55 AND 65
    AND a.hadm_id IN (SELECT hadm_id FROM pneumonia_patients)
),

score_data AS (
  SELECT 
    e.stay_id,
    e.los,
    e.hospital_expire_flag,
    c.valuenum AS instability_score
  FROM eligible_patients e
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c ON e.stay_id = c.stay_id
  WHERE 
    c.itemid = 220045
    AND c.charttime BETWEEN e.intime AND e.intime + INTERVAL '24' HOUR
    AND c.valuenum IS NOT NULL
),

deciles AS (
  SELECT 
    *,
    NTILE(10) OVER (ORDER BY instability_score DESC) AS decile
  FROM score_data
)

SELECT 
  (COUNT(CASE WHEN instability_score <= 60 THEN 1 END) * 100.0 / COUNT(*)) AS percentile_of_60,
  AVG(los) AS avg_los_top_decile,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate_top_decile
FROM deciles
WHERE decile = 1;