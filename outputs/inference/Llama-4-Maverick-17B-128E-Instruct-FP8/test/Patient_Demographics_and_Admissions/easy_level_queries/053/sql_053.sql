WITH 
-- Filter patients who are female and between 52 and 62 years old
eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 52 AND 62
),

-- Identify admissions for these patients
eligible_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN eligible_patients p ON a.subject_id = p.subject_id
),

-- Identify AKI admissions using ICD codes
aki_admissions AS (
  SELECT DISTINCT e.hadm_id
  FROM eligible_admissions e
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON e.hadm_id = d.hadm_id
  WHERE d.icd_code IN ('N17.0', 'N17.1', 'N17.2', 'N17.8', 'N17.9')  -- Example ICD-10 codes for AKI
  AND d.icd_version = 10  -- Assuming ICD-10; adjust as necessary
),

-- Calculate 30-day readmission
readmissions AS (
  SELECT 
    e.hadm_id,
    LEAD(e.admittime, 1) OVER (PARTITION BY e.subject_id ORDER BY e.admittime) AS next_admittime,
    e.dischtime,
    CASE 
      WHEN LEAD(e.admittime, 1) OVER (PARTITION BY e.subject_id ORDER BY e.admittime) <= (e.dischtime + INTERVAL 30 DAY)
      THEN 1
      ELSE 0
    END AS readmitted_within_30_days
  FROM eligible_admissions e
  WHERE e.hadm_id IN (SELECT hadm_id FROM aki_admissions)
),

-- Calculate standard deviation of 30-day readmission
std_dev_readmission AS (
  SELECT 
    STDDEV(readmitted_within_30_days) AS std_dev
  FROM readmissions
)

SELECT std_dev
FROM std_dev_readmission;