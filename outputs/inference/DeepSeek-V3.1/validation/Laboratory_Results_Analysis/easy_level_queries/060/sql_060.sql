WITH pneumonia_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON p.subject_id = adm.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age = 67
    AND diag.icd_version = 10
    AND d.icd_code LIKE 'J18%'
),
glucose_first_24h AS (
  SELECT pa.hadm_id, le.valuenum
  FROM pneumonia_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON pa.hadm_id = le.hadm_id
    AND le.charttime BETWEEN pa.admittime AND DATETIME_ADD(pa.admittime, INTERVAL 24 HOUR)
  WHERE le.itemid = 50809  -- Glucose (serum)
    AND le.valuenum IS NOT NULL
),
mean_glucose_per_admission AS (
  SELECT hadm_id, AVG(valuenum) AS avg_glucose
  FROM glucose_first_24h
  GROUP BY hadm_id
)
SELECT APPROX_QUANTILES(avg_glucose, 100)[OFFSET(75)] AS percentile_75
FROM mean_glucose_per_admission;