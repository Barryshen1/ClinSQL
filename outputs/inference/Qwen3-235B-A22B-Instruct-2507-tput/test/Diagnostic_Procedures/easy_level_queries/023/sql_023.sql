WITH cardiac_keywords AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE LOWER(long_title) LIKE '%heart%'
     OR LOWER(long_title) LIKE '%cardiac%'
     OR LOWER(long_title) LIKE '%coronary%'
     OR LOWER(long_title) LIKE '%valve%'
     OR LOWER(long_title) LIKE '%angioplasty%'
     OR LOWER(long_title) LIKE '%bypass%'
     OR LOWER(long_title) LIKE '%pacemaker%'
     OR LOWER(long_title) LIKE '%defibrillator%'
     OR LOWER(long_title) LIKE '%electrophysiology%'
     OR LOWER(long_title) LIKE '%cardioversion%'
     OR LOWER(long_title) LIKE '%pericardial%'
),
patient_admissions AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 82 AND 92
),
admission_procedure_counts AS (
  SELECT
    pa.hadm_id,
    COUNT(DISTINCT pi.icd_code) AS distinct_cardiac_proc_count
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    ON pa.hadm_id = pi.hadm_id
  INNER JOIN cardiac_keywords ck
    ON pi.icd_code = ck.icd_code
  WHERE pi.icd_version = 10  -- Focus on ICD-10-PCS
  GROUP BY pa.hadm_id
)
SELECT
  PERCENTILE_CONT(distinct_cardiac_proc_count, 0.25) OVER() AS percentile_25
FROM admission_procedure_counts
LIMIT 1;