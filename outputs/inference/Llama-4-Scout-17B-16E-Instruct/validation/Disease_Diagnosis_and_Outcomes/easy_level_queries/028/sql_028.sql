WITH 
  -- Identify female patients aged 67-77
  eligible_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'F' AND anchor_age BETWEEN 67 AND 77
  ),
  
  -- Identify admissions with primary community-acquired pneumonia
  cap_admissions AS (
    SELECT a.hadm_id, a.admittime, a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN eligible_patients ep ON a.subject_id = ep.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
    WHERE d.seq_num = 1 AND dd.long_title LIKE '%Community-acquired pneumonia%'
  ),
  
  -- Calculate hospital length of stay
  los AS (
    SELECT hadm_id, 
           DATE_DIFF(dischtime, admittime, 'DAY') AS los_days
    FROM cap_admissions
  )

-- Calculate 25th percentile of hospital length of stay
SELECT APPROX_QUANTILES(los_days, 0.25)[OFFSET(1)] AS percentile_25_los
FROM los;