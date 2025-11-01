WITH heart_failure_patients AS (
  SELECT DISTINCT p.subject_id
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON p.subject_id = d.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age = 74
    AND (
      -- ICD-10 I50.x or ICD-9 428.x
      (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I50'))
      OR
      (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^428'))
    )
),

admissions_filtered AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.admission_type
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN heart_failure_patients hfp ON a.subject_id = hfp.subject_id
),

admissions_los AS (
  SELECT
    subject_id,
    hadm_id,
    admission_type,
    admittime,
    dischtime,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days,
    CASE
      WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 4 THEN '1-4'
      WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) BETWEEN 5 AND 7 THEN '5-7'
      ELSE NULL
    END AS los_group
  FROM admissions_filtered
  WHERE TIMESTAMP_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 7
),

noninvasive_procedures AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.icd_code,
    pr.icd_version,
    dp.long_title
  FROM physionet-data.mimiciv_3_1_hosp.procedures_icd pr
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_procedures dp
    ON pr.icd_code = dp.icd_code AND pr.icd_version = dp.icd_version
  WHERE
    -- Imaging modalities
    REGEXP_CONTAINS(LOWER(dp.long_title), r'(x-ray|ct|mri|ultrasound|radiology|imaging|pet scan|nuclear medicine)')
    OR
    -- ECG/EEG/PFT
    REGEXP_CONTAINS(LOWER(dp.long_title), r'(ecg|electrocardiogram|eeg|electroencephalogram|pft|pulmonary function test)')
),

diagnostics_per_admission AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admission_type,
    a.los_group,
    COUNT(DISTINCT np.icd_code) AS num_diagnostics
  FROM admissions_los a
  LEFT JOIN noninvasive_procedures np
    ON a.subject_id = np.subject_id AND a.hadm_id = np.hadm_id
  WHERE a.los_group IS NOT NULL
  GROUP BY a.subject_id, a.hadm_id, a.admission_type, a.los_group
),

admission_type_group AS (
  SELECT
    CASE
      WHEN LOWER(admission_type) IN ('ed', 'urgent') THEN 'ED/Urgent'
      WHEN LOWER(admission_type) = 'elective' THEN 'Elective'
      ELSE 'Other'
    END AS admission_type_group,
    los_group,
    num_diagnostics
  FROM diagnostics_per_admission
)

SELECT
  admission_type_group,
  los_group,
  COUNT(*) AS num_admissions,
  ROUND(AVG(num_diagnostics),2) AS mean_noninvasive_diagnostics_per_admission
FROM admission_type_group
WHERE admission_type_group IN ('ED/Urgent', 'Elective')
  AND los_group IN ('1-4', '5-7')
GROUP BY admission_type_group, los_group
ORDER BY admission_type_group, los_group;