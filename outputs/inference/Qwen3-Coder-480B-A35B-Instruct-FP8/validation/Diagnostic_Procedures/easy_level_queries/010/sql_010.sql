WITH echocardiography_codes AS (
  -- Identify ICD codes for echocardiography
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE LOWER(long_title) LIKE '%echocardiography%'
),
filtered_patients AS (
  -- Select male patients aged 84–94
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 84 AND 94
),
procedure_counts AS (
  -- Count echocardiography procedures per hospital admission
  SELECT p.subject_id, p.hadm_id, COUNT(*) AS proc_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN filtered_patients fp ON p.subject_id = fp.subject_id
  JOIN echocardiography_codes ec ON p.icd_code = ec.icd_code AND p.icd_version = ec.icd_version
  GROUP BY p.subject_id, p.hadm_id
)
-- Get the maximum number of procedures across all admissions
SELECT MAX(proc_count) AS max_echocardiography_procedures
FROM procedure_counts;