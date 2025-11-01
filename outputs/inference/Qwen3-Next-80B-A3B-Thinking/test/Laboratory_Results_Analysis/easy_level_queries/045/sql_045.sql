WITH sepsis_admissions AS (
  SELECT DISTINCT a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (di.long_title LIKE '%sepsis%' OR di.long_title LIKE '%septicemia%')
),
creatinine_measurements AS (
  SELECT 
    s.hadm_id, 
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY s.hadm_id ORDER BY l.charttime) AS rn
  FROM sepsis_admissions s
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON s.hadm_id = l.hadm_id
    AND l.itemid = 50912
    AND l.charttime BETWEEN s.admittime AND s.dischtime
    AND l.valuenum IS NOT NULL
)
SELECT MAX(valuenum) AS max_admission_creatinine
FROM creatinine_measurements
WHERE rn = 1;