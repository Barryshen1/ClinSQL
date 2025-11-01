WITH patients_with_birth_date AS (
  SELECT 
    subject_id,
    DATE_SUB(CAST(CONCAT(anchor_year, '-01-01') AS DATE), INTERVAL anchor_age YEAR) AS birth_date
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
),
filtered_admissions AS (
  SELECT 
    a.subject_id, 
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN patients_with_birth_date p 
    ON a.subject_id = p.subject_id
  WHERE FLOOR(DATE_DIFF(a.admittime, p.birth_date, DAY) / 365.25) BETWEEN 57 AND 67
),
echocardiography_procedures AS (
  SELECT 
    f.subject_id,
    p.icd_code
  FROM filtered_admissions f
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p 
    ON f.hadm_id = p.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE d.long_title LIKE '%echocardiography%'
),
distinct_procedures_per_patient AS (
  SELECT 
    subject_id,
    COUNT(DISTINCT icd_code) AS distinct_procedure_count
  FROM echocardiography_procedures
  GROUP BY subject_id
),
all_patients AS (
  SELECT DISTINCT subject_id
  FROM filtered_admissions
)
SELECT 
  APPROX_QUANTILES(IFNULL(dp.distinct_procedure_count, 0), 100)[OFFSET(75)] AS p75_distinct_procedures
FROM all_patients a
LEFT JOIN distinct_procedures_per_patient dp 
  ON a.subject_id = dp.subject_id;