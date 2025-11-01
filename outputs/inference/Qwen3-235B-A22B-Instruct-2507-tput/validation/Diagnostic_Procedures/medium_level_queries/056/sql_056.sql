WITH patient_admissions AS (
  SELECT
    a.hadm_id,
    p.subject_id,
    -- Calculate age at admission
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission,
    -- Calculate LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN
    `physionet-data.mimiciv_3_1_hosp`.patients p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.hospital_expire_flag = 0  -- Exclude in-hospital deaths if they affect imaging likelihood?
),
pancreatitis_admissions AS (
  SELECT DISTINCT
    pa.hadm_id,
    pa.subject_id,
    pa.age_at_admission,
    pa.los_days
  FROM
    patient_admissions pa
  JOIN
    `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  ON
    pa.hadm_id = di.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d_diag
  ON
    di.icd_code = d_diag.icd_code
    AND di.icd_version = d_diag.icd_version
  WHERE
    pa.age_at_admission BETWEEN 47 AND 57
    AND (
      (d_diag.icd_version = 10 AND d_diag.icd_code LIKE 'K85%') OR
      (d_diag.icd_version = 9 AND d_diag.icd_code = '5770')
    )
),
imaging_procs AS (
  SELECT
    pi.hadm_id,
    COUNT(*) AS ct_mri_count
  FROM
    `physionet-data.mimiciv_3_1_hosp`.procedures_icd pi
  JOIN
    `physionet-data.mimiciv_3_1_hosp`.d_icd_procedures dp
  ON
    pi.icd_code = dp.icd_code
    AND pi.icd_version = dp.icd_version
  WHERE
    LOWER(dp.long_title) LIKE '%computed tomography%' 
    OR LOWER(dp.long_title) LIKE '%ct%'
    OR LOWER(dp.long_title) LIKE '%magnetic resonance%'
    OR LOWER(dp.long_title) LIKE '%mri%'
    -- Focus on abdomen/pancreas if possible, but broad capture is safer
  GROUP BY
    pi.hadm_id
),
admissions_with_imaging AS (
  SELECT
    pa.hadm_id,
    pa.los_days,
    COALESCE(ip.ct_mri_count, 0) AS ct_mri_count
  FROM
    pancreatitis_admissions pa
  LEFT JOIN
    imaging_procs ip
  ON
    pa.hadm_id = ip.hadm_id
  WHERE
    pa.los_days BETWEEN 1 AND 8  -- Restrict to 1–8 days
),
los_groups AS (
  SELECT
    hadm_id,
    ct_mri_count,
    CASE
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN los_days BETWEEN 5 AND 8 THEN '5-8 days'
    END AS los_group
  FROM
    admissions_with_imaging
)
SELECT
  los_group,
  COUNT(*) AS patient_count,
  AVG(ct_mri_count) AS mean_ct_mri_per_admission
FROM
  los_groups
GROUP BY
  los_group
ORDER BY
  los_group;