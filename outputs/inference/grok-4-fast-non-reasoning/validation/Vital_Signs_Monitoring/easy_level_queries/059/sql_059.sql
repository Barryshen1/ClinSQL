WITH eligible_patients AS (
  -- Select male patients aged 77-87 with first admissions
  SELECT 
    p.subject_id,
    p.anchor_age,
    a.admittime,
    a.hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
  QUALIFY 
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) = 1
),
first_icu_stays AS (
  -- Get first ICU stay for each eligible patient's first admission
  SELECT 
    ep.subject_id,
    fis.stay_id,
    fis.intime,
    fis.hadm_id
  FROM 
    eligible_patients ep
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` fis
  ON 
    ep.subject_id = fis.subject_id 
    AND ep.hadm_id = fis.hadm_id
  QUALIFY 
    ROW_NUMBER() OVER (PARTITION BY ep.subject_id ORDER BY fis.intime) = 1
),
first_spo2 AS (
  -- Get first valid SpO2 within 24h of ICU admission per stay
  SELECT 
    fis.subject_id,
    ce.valuenum AS first_spo2
  FROM 
    first_icu_stays fis
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON 
    fis.subject_id = ce.subject_id
    AND fis.hadm_id = ce.hadm_id
    AND fis.stay_id = ce.stay_id
  WHERE 
    ce.itemid = 220277  -- SpO2 %
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 0 AND 100
    AND ce.charttime >= fis.intime
    AND ce.charttime <= DATE_ADD(fis.intime, INTERVAL 1 DAY)
  QUALIFY 
    ROW_NUMBER() OVER (PARTITION BY fis.subject_id ORDER BY ce.charttime) = 1
)
-- Compute standard deviation of first SpO2 values
SELECT 
  STDDEV(first_spo2) AS stddev_first_spo2
FROM 
  first_spo2;