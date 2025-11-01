WITH tia_patients AS (
  -- Identify TIA admissions for female patients aged 50-60
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON diag.icd_code = dd.icd_code AND diag.icd_version = dd.icd_version
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 50 AND 60
    AND (
      -- ICD-10 TIA: G45.9
      (diag.icd_version = 10 AND diag.icd_code LIKE 'G45%')
      -- ICD-9 TIA: 435.x
      OR (diag.icd_version = 9 AND diag.icd_code LIKE '435%')
      -- Also allow long_title contains 'transient ischemic attack'
      OR LOWER(dd.long_title) LIKE '%transient ischemic attack%'
    )
),
ct_mri_procs AS (
  -- Identify CT/MRI procedures per admission
  SELECT
    proc.subject_id,
    proc.hadm_id,
    COUNT(*) AS ct_mri_proc_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON proc.icd_code = dp.icd_code AND proc.icd_version = dp.icd_version
  WHERE
    LOWER(dp.long_title) LIKE '%ct%'
    OR LOWER(dp.long_title) LIKE '%mri%'
  GROUP BY
    proc.subject_id, proc.hadm_id
),
admission_ct_mri AS (
  -- Join TIA admissions with CT/MRI procedure counts
  SELECT
    t.subject_id,
    t.hadm_id,
    t.los_days,
    IFNULL(c.ct_mri_proc_count, 0) AS ct_mri_proc_count
  FROM
    tia_patients t
  LEFT JOIN
    ct_mri_procs c
    ON t.subject_id = c.subject_id AND t.hadm_id = c.hadm_id
)
SELECT
  CASE
    WHEN los_days BETWEEN 1 AND 3 THEN 'LOS 1-3 days'
    WHEN los_days BETWEEN 4 AND 7 THEN 'LOS 4-7 days'
    ELSE NULL
  END AS los_group,
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(*) AS admission_count,
  ROUND(AVG(ct_mri_proc_count), 2) AS mean_ct_mri_procs_per_admission
FROM
  admission_ct_mri
WHERE
  los_days BETWEEN 1 AND 7
GROUP BY
  los_group
ORDER BY
  los_group;