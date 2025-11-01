WITH 
-- Identify patients with ACS and elevated Troponin T
acs_patients AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    le.valuenum AS troponin_level
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.labevents` le 
      ON a.hadm_id = le.hadm_id 
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_labitems` dli 
      ON le.itemid = dli.itemid
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
      ON a.hadm_id = di.hadm_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
      ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE 
    a.subject_id IN (
      SELECT 
        subject_id 
      FROM 
        `physionet-data.mimiciv_3_1_hosp.patients` 
      WHERE 
        gender = 'M' AND 
        anchor_age BETWEEN 73 AND 83
    )
    AND dd.long_title LIKE '%Acute coronary syndrome%'
    AND dli.label = 'Troponin T'
    AND le.charttime = ( 
      SELECT 
        MIN(charttime) 
      FROM 
        `physionet-data.mimiciv_3_1_hosp.labevents` 
      WHERE 
        hadm_id = a.hadm_id AND 
        itemid = le.itemid
    )
    AND le.valuenum > 0  -- Assuming elevated Troponin T is above 0
),

-- Calculate length of stay and in-hospital mortality
patient_stats AS (
  SELECT 
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    hospital_expire_flag,
    troponin_level,
    DATE_DIFF(dischtime, admittime, DAY) AS length_of_stay
  FROM 
    acs_patients
)

-- Calculate cohort statistics
SELECT 
  AVG(length_of_stay) AS avg_length_of_stay,
  SUM(hospital_expire_flag) / COUNT(*) AS in_hospital_mortality_rate
FROM 
  patient_stats;