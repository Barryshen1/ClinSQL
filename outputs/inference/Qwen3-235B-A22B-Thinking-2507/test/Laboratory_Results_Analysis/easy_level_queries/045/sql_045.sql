WITH sepsis_admissions AS (
  SELECT DISTINCT a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND d.icd_version = 10
    AND (d.icd_code LIKE 'A40%' OR d.icd_code LIKE 'A41%' OR d.icd_code LIKE 'R652%')
),
first_creat AS (
  SELECT 
    sa.hadm_id,
    le.valuenum,
    ROW_NUMBER() OVER (
      PARTITION BY sa.hadm_id 
      ORDER BY le.charttime
    ) AS rn
  FROM sepsis_admissions sa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON sa.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  WHERE 
    dli.label = 'CREATININE'
    AND le.charttime >= sa.admittime
    AND le.charttime <= sa.admittime + INTERVAL 24 HOUR
    AND le.valuenum IS NOT NULL
)
SELECT MAX(valuenum) AS max_admission_creatinine
FROM first_creat
WHERE rn = 1;