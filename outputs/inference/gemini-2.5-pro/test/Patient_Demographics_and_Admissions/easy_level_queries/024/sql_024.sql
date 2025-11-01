with '36.1' or ICD-10-PCS codes starting with '021'.
WITH cabg_procedures AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  WHERE
    (icd_version = 9 AND icd_code LIKE '36.1%')
    OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) = '021')
),

-- Define a CTE to find the first hospital admission for each patient.
-- This is done by ranking admissions by their admission time.
first_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS admission_rank
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
)

-- Main query to calculate in-hospital mortality for the specified cohort.
SELECT
  COUNT(adm.hadm_id) AS total_patients,
  SUM(adm.hospital_expire_flag) AS in_hospital_deaths,
  SAFE_DIVIDE(SUM(adm.hospital_expire_flag), COUNT(adm.hadm_id)) * 100 AS in_hospital_mortality_percentage
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` AS pat
-- Join to get only the first admission for each patient.
INNER JOIN
  first_admissions AS adm
  ON pat.subject_id = adm.subject_id
  AND adm.admission_rank = 1
-- Join to get only admissions where a CABG procedure was performed.
INNER JOIN
  cabg_procedures AS cabg
  ON adm.hadm_id = cabg.hadm_id
-- Apply filters for female patients aged 35-45.
WHERE
  pat.gender = 'F'
  AND pat.anchor_age BETWEEN 35 AND 45;