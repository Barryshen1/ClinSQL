WITH female_pneumonia_admissions AS (
  SELECT DISTINCT a.hadm_id, a.admittime, p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE p.gender = 'F'
    AND LOWER(d.long_title) LIKE '%pneumonia%'
    -- Alternatively, use ICD code pattern: d.icd_code LIKE 'J18%' AND di.icd_version = 10
),
creatinine_values_24h AS (
  SELECT
    fa.hadm_id,
    AVG(le.valuenum) AS avg_creatinine_24h
  FROM female_pneumonia_admissions fa
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON fa.hadm_id = le.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli ON le.itemid = dli.itemid
  WHERE dli.label = 'Creatinine'
    AND LOWER(dli.fluid) = 'blood'
    AND le.valuenum IS NOT NULL
    AND le.charttime >= fa.admittime
    AND le.charttime < DATETIME_ADD(fa.admittime, INTERVAL 24 HOUR)
  GROUP BY fa.hadm_id
)
SELECT MIN(avg_creatinine_24h) AS min_24h_avg_serum_creatinine
FROM creatinine_values_24h;