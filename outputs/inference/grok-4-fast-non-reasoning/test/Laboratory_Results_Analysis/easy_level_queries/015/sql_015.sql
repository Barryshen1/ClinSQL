WITH female_pneumonia_patients AS (
  -- Identify female patients with pneumonia diagnoses
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code
    AND d.icd_version = icd.icd_version
  WHERE p.gender = 'F'
    AND icd.icd_version = 10  -- Focus on ICD-10 for modern relevance
    AND (icd.icd_code LIKE 'J12%' OR icd.icd_code LIKE 'J15%' OR icd.icd_code LIKE 'J18%')  -- Specific pneumonia codes
),
creatinine_labs AS (
  -- Extract serum creatinine labs during admission
  SELECT 
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON le.itemid = li.itemid
  INNER JOIN female_pneumonia_patients fpp
    ON le.subject_id = fpp.subject_id
    AND le.hadm_id = fpp.hadm_id
  WHERE li.label LIKE '%creatinine%'
    AND le.valuenum IS NOT NULL
    AND le.valuenum > 0
    AND le.valuenum < 20  -- Reasonable upper bound to exclude errors
    AND le.charttime >= fpp.admittime
    AND le.charttime <= fpp.dischtime
),
hourly_averages AS (
  -- Compute 24-hour rolling average for each creatinine event
  SELECT 
    cl.subject_id,
    cl.hadm_id,
    cl.charttime,
    AVG(cl2.valuenum) AS avg_24h_creatinine
  FROM creatinine_labs cl
  LEFT JOIN creatinine_labs cl2
    ON cl2.subject_id = cl.subject_id
    AND cl2.hadm_id = cl.hadm_id
    AND cl2.charttime <= cl.charttime
    AND cl2.charttime > cl.charttime - INTERVAL 24 HOUR
  GROUP BY cl.subject_id, cl.hadm_id, cl.charttime
  HAVING avg_24h_creatinine IS NOT NULL  -- Exclude windows with no labs
)
-- Compute minimum 24-hour average per patient (across all their admissions if multiple)
SELECT 
  MIN(avg_24h_creatinine) AS min_24h_avg_serum_creatinine
FROM hourly_averages;