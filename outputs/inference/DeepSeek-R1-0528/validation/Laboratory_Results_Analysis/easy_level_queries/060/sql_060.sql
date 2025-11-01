WITH pneumonia_admissions AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag.icd_code = d.icd_code 
    AND diag.icd_version = d.icd_version
  WHERE 
    pat.gender = 'M'
    AND pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) = 67
    AND LOWER(d.long_title) LIKE '%pneumonia%'
),
first_24h_glucose AS (
  SELECT 
    pa.hadm_id,
    lab.valuenum AS glucose_value
  FROM pneumonia_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` lab
    ON pa.hadm_id = lab.hadm_id
    AND lab.itemid IN (50931, 50809)  -- Serum glucose itemids
    AND lab.valuenum IS NOT NULL      -- Ensure numeric value
    AND lab.charttime >= pa.admittime
    AND lab.charttime <= DATETIME_ADD(pa.admittime, INTERVAL 24 HOUR)
),
mean_glucose_per_admission AS (
  SELECT 
    hadm_id, 
    AVG(glucose_value) AS mean_glucose
  FROM first_24h_glucose
  GROUP BY hadm_id
)
SELECT 
  APPROX_QUANTILES(mean_glucose, 100)[OFFSET(75)] AS percentile_75_mean_glucose
FROM mean_glucose_per_admission;