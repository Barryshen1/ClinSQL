WITH cabg_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE LOWER(long_title) LIKE '%coronary artery bypass%'
     OR LOWER(long_title) LIKE '%cabg%'
),
patients_filtered AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 41 AND 51
),
patient_procedure_counts AS (
  SELECT
    pf.subject_id,
    COUNT(*) AS procedure_count
  FROM patients_filtered pf
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    ON pf.subject_id = p.subject_id
  INNER JOIN cabg_codes c
    ON p.icd_code = c.icd_code AND p.icd_version = c.icd_version
  GROUP BY pf.subject_id
)
SELECT
  STDDEV_POP(procedure_count) AS std_dev_cabg_procedures_per_patient
FROM patient_procedure_counts;