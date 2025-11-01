WITH 
  -- Identify creatinine itemid
  creatinine_item AS (
    SELECT itemid 
    FROM `physionet-data.mimiciv_3_1_hosp.d_labitems` 
    WHERE label LIKE '%Creatinine%'
  ),
  
  -- Select relevant patients and admissions
  patients_admissions AS (
    SELECT a.subject_id, a.hadm_id, a.admittime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
    WHERE p.gender = 'M' 
      AND p.anchor_age BETWEEN 45 AND 55
      AND a.discharge_location LIKE '%pneumonia%'
  ),
  
  -- Extract creatinine levels within the first 24 hours
  creatinine_levels AS (
    SELECT a.hadm_id, 
           le.valuenum AS creatinine,
           TIMESTAMP_DIFF(le.charttime, a.admittime, HOUR) AS hours_since_admission
    FROM patients_admissions a
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le 
      ON a.hadm_id = le.hadm_id
    JOIN creatinine_item ci 
      ON le.itemid = ci.itemid
    WHERE le.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 24 HOUR)
  )

-- Calculate average creatinine per patient and then the SD of these averages
SELECT 
  STDDEV(avg_creatinine) AS std_dev_average_creatinine
FROM (
  SELECT 
    hadm_id,
    AVG(creatinine) AS avg_creatinine
  FROM creatinine_levels
  WHERE hours_since_admission >= 0 AND hours_since_admission <= 24
  GROUP BY hadm_id
);