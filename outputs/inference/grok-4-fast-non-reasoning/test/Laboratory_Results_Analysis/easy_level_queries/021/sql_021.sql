WITH pneumonia_admissions AS (
  SELECT DISTINCT 
    a.subject_id,
    a.hadm_id,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND a.hospital_expire_flag = 0
    AND a.dischtime IS NOT NULL
    AND d.icd_version = '10'
    AND d.seq_num = 1
    AND (LOWER(d.icd_code) LIKE 'J12%' 
         OR LOWER(d.icd_code) LIKE 'J13%' 
         OR LOWER(d.icd_code) LIKE 'J14%' 
         OR LOWER(d.icd_code) LIKE 'J15%' 
         OR LOWER(d.icd_code) LIKE 'J18%')
)
SELECT 
  PERCENTILE_CONT(0.75) OVER() AS p75_serum_glucose
FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
INNER JOIN pneumonia_admissions pa
  ON le.subject_id = pa.subject_id
  AND le.hadm_id = pa.hadm_id
WHERE le.itemid = CAST(225655 AS INT64)
  AND le.valuenum IS NOT NULL
  AND le.valuenum > 0
  AND DATE(le.charttime) >= DATE(pa.dischtime) - 1
  AND DATE(le.charttime) <= DATE(pa.dischtime)
  AND EXTRACT(HOUR FROM le.charttime) >= 12
  AND le.charttime <= pa.dischtime;