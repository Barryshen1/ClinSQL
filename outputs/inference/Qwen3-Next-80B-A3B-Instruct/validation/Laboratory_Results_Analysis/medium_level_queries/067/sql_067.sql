WITH amipatients AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    le.valuenum AS troponin_t_value,
    le.charttime AS troponin_charttime,
    ROW_NUMBER() OVER (PARTITION BY a.hadm_id ORDER BY le.charttime ASC) AS rn
  FROM 
    physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.admissions a 
    ON p.subject_id = a.subject_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd di 
    ON a.hadm_id = di.hadm_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did 
    ON di.icd_code = did.icd_code AND di.icd_version = did.icd_version
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.labevents le 
    ON a.hadm_id = le.hadm_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.d_labitems dl 
    ON le.itemid = dl.itemid
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
    AND LOWER(did.long_title) LIKE '%acute myocardial infarction%'
    AND LOWER(dl.label) LIKE '%troponin t%'
    AND le.valuenum IS NOT NULL
    AND le.valuenum > 0.01
),
first_troponin AS (
  SELECT *
  FROM amipatients
  WHERE rn = 1
)
SELECT 
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(*) AS admission_count,
  AVG(anchor_age) AS mean_age,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, DAY)) AS mean_los,
  MIN(troponin_t_value) AS first_troponin_min,
  MAX(troponin_t_value) AS first_troponin_max,
  AVG(troponin_t_value) AS first_troponin_mean,
  COUNT(troponin_t_value) AS first_troponin_count,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS in_hospital_mortality_rate
FROM 
  first_troponin;