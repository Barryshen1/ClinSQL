WITH initial_troponin AS (
  SELECT 
    le.hadm_id,
    le.valuenum AS troponin_t_value,
    le.charttime,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM 
    physionet-data.mimiciv_3_1_hosp.labevents le
  JOIN 
    physionet-data.mimiciv_3_1_hosp.d_labitems d ON le.itemid = d.itemid
  WHERE 
    d.label = 'Troponin T'
    AND le.valuenum > 0.01  -- elevated threshold
),
acs_admissions AS (
  SELECT DISTINCT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM 
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN 
    physionet-data.mimiciv_3_1_hosp.patients p ON a.subject_id = p.subject_id
  JOIN 
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd di ON a.hadm_id = di.hadm_id
  JOIN 
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd ON di.icd_code = dicd.icd_code 
    AND di.icd_version = dicd.icd_version
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
    AND dicd.icd_code IN (
      'I21.0', 'I21.1', 'I21.2', 'I21.3', 'I21.4', 'I21.9',  -- AMI
      'I22.0', 'I22.1', 'I22.2', 'I22.8', 'I22.9',           -- Subsequent MI
      'I24.8', 'I24.9',                                      -- Other acute ischemic heart disease
      'I20.0'                                                -- Unstable angina
    )
)
SELECT 
  AVG(EXTRACT(DAY FROM (a.dischtime - a.admittime))) AS avg_length_of_stay_days,
  AVG(CAST(a.hospital_expire_flag AS FLOAT64)) AS in_hospital_mortality_rate,
  COUNT(*) AS cohort_size
FROM 
  acs_admissions a
JOIN 
  initial_troponin it ON a.hadm_id = it.hadm_id
WHERE 
  it.rn = 1;