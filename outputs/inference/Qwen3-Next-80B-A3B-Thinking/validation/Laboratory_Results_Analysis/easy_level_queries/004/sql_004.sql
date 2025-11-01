WITH sepsis_patients AS (
  SELECT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE di.long_title LIKE '%sepsis%'
),
filtered_patients AS (
  SELECT p.subject_id, p.anchor_age, p.gender, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN sepsis_patients s ON a.hadm_id = s.hadm_id
  WHERE p.gender = 'F' AND p.anchor_age = 76
),
platelet_24h AS (
  SELECT 
    f.hadm_id,
    AVG(l.valuenum) AS avg_platelet
  FROM filtered_patients f
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON f.hadm_id = l.hadm_id
    AND l.itemid = 51265
    AND l.charttime BETWEEN f.admittime AND DATETIME_ADD(f.admittime, INTERVAL 24 HOUR)
  WHERE l.valuenum IS NOT NULL
  GROUP BY f.hadm_id
)
SELECT PERCENTILE_CONT(avg_platelet, 0.5) OVER () AS median_platelet
FROM platelet_24h
LIMIT 1;