WITH 
-- Step 1: Identify male patients with sepsis (using diagnoses_icd as a proxy) and include admittime
sepsis_patients AS (
  SELECT DISTINCT h.subject_id, h.hadm_id, h.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON h.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON h.subject_id = d.subject_id AND h.hadm_id = d.hadm_id
  WHERE p.gender = 'M' AND d.icd_code LIKE 'A41%'  -- Using sepsis ICD codes as a proxy
),

-- Step 2 & 3: Find admission serum creatinine for these patients
admission_creatinine AS (
  SELECT s.hadm_id, l.valuenum AS creatinine
  FROM sepsis_patients s
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON s.subject_id = l.subject_id AND s.hadm_id = l.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl ON l.itemid = dl.itemid
  WHERE dl.label = 'Creatinine' AND l.charttime BETWEEN s.admittime AND TIMESTAMP_ADD(s.admittime, INTERVAL 1 DAY)
),

-- Step 4: Calculate the maximum admission serum creatinine
max_creatinine AS (
  SELECT MAX(creatinine) AS max_creatinine
  FROM admission_creatinine
)

SELECT max_creatinine
FROM max_creatinine;