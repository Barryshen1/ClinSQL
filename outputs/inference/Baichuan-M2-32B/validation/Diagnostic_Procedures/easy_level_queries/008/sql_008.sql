WITH female_patients AS (
  SELECT
    subject_id,
    DATE_SUB(CAST(CONCAT(anchor_year, '-01-01') AS DATE), INTERVAL anchor_age YEAR) AS birth_date
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
),
admissions_with_age AS (
  SELECT
    fp.subject_id,
    a.hadm_id,
    a.admittime,
    TIMESTAMP_DIFF(a.admittime, fp.birth_date, YEAR) AS age_at_admission
  FROM female_patients fp
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON fp.subject_id = a.subject_id
),
eligible_admissions AS (
  SELECT
    subject_id,
    hadm_id
  FROM admissions_with_age
  WHERE age_at_admission BETWEEN 88 AND 98
),
echocardiography_procedures AS (
  SELECT
    ea.subject_id,
    pr.icd_code
  FROM eligible_admissions ea
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON ea.subject_id = pr.subject_id
    AND ea.hadm_id = pr.hadm_id
    AND pr.icd_code IN ('37.23', '37.24', '37.29')
    AND pr.icd_version = 9
),
patient_procedure_counts AS (
  SELECT
    subject_id,
    COUNT(DISTINCT icd_code) AS distinct_echocardiography_procedures
  FROM echocardiography_procedures
  GROUP BY subject_id
)
SELECT
  APPROX_QUANTILES(distinct_echocardiography_procedures, 100)[OFFSET(25)] AS p25
FROM patient_procedure_counts;