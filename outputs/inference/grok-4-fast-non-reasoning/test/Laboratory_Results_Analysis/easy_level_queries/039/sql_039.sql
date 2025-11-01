WITH pneumonia_admissions AS (
  SELECT DISTINCT 
    p.subject_id,
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
    AND d.icd_version = icd.icd_version
  WHERE p.gender = 'M'
    AND CAST(p.anchor_age AS INT64) = 95
    AND d.icd_version = 10  -- Focus on ICD-10 for modern pneumonia codes
    AND REGEXP_CONTAINS(d.icd_code, r'^J[0-9]{2}\.?\d*')  -- Pneumonia category (J00-J99)
),
peak_creatinine AS (
  SELECT 
    pa.hadm_id,
    MAX(le.valuenum) AS peak_creat
  FROM pneumonia_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON pa.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON le.itemid = li.itemid
  WHERE le.valuenum IS NOT NULL
    AND le.valueuom = 'mg/dL'
    AND li.category = 'Chemistry'
    AND li.label LIKE '%creatinine%'  -- Ensures serum creatinine
    AND le.charttime BETWEEN pa.admittime AND pa.dischtime
  GROUP BY pa.hadm_id
  HAVING peak_creat IS NOT NULL
)
SELECT 
  STDDEV(peak_creat) AS stddev_peak_serum_creatinine
FROM peak_creatinine;