WITH pneumonia_male_admissions AS (
  SELECT a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND LOWER(d_icd.long_title) LIKE '%pneumonia%'
),
glucose_in_first_24h AS (
  SELECT 
    le.hadm_id,
    le.valuenum AS glucose_value
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl ON le.itemid = dl.itemid
  INNER JOIN pneumonia_male_admissions pma ON le.hadm_id = pma.hadm_id
  WHERE LOWER(dl.label) LIKE '%glucose%'
    AND le.valuenum IS NOT NULL
    AND le.charttime >= pma.admittime
    AND le.charttime < TIMESTAMP_ADD(pma.admittime, INTERVAL 24 HOUR)
),
mean_glucose_per_admission AS (
  SELECT 
    hadm_id,
    AVG(glucose_value) AS mean_glucose
  FROM glucose_in_first_24h
  GROUP BY hadm_id
)
SELECT 
  APPROX_QUANTILES(mean_glucose, 100)[OFFSET(75)] AS p75_mean_glucose
FROM mean_glucose_per_admission;