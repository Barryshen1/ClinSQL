WITH sepsis_patients AS (
  SELECT DISTINCT 
    p.subject_id,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code 
    AND d.icd_version = SAFE_CAST(icd.icd_version AS INT64)
  WHERE p.gender = 'M'
    AND (
      (CAST(d.icd_version AS STRING) = '10' AND (d.icd_code LIKE 'A41%' OR d.icd_code LIKE 'R65%'))
      OR 
      (CAST(d.icd_version AS STRING) = '9' AND (d.icd_code LIKE '038.%' OR d.icd_code LIKE '995.91'))
    )
),
patient_peaks AS (
  SELECT 
    sp.subject_id,
    MAX(le.valuenum) AS peak_platelet
  FROM sepsis_patients sp
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON sp.subject_id = le.subject_id 
    AND sp.hadm_id = le.hadm_id
    AND le.itemid = 50592  -- Platelet count
    AND le.valuenum > 0
    AND le.charttime BETWEEN sp.admittime AND sp.dischtime
  GROUP BY sp.subject_id
  HAVING peak_platelet IS NOT NULL
)
SELECT 
  PERCENTILE_CONT(peak_platelet, 0.75) AS p75_peak_platelet
FROM patient_peaks;