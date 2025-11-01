WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.icustays` ic
      WHERE ic.hadm_id = a.hadm_id
    ) THEN 'ICU' ELSE 'Non-ICU' END AS icu_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
    -- approximate "asthma exacerbation" by diagnosis containing 'asthma' (primary diagnosis)
    AND d.seq_num = 1
    AND LOWER(dd.long_title) LIKE '%asthma%'
    -- limit to LOS between 1 and 8 days (inclusive); will bucket into 1-4 and 5-8
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 8
),

hcpc_imaging AS (
  SELECT
    hadm_id,
    COUNT(*) AS hcpc_ct_mri_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
  WHERE
    -- heuristic keyword matching for CT/MRI in the short_description
    (
      LOWER(COALESCE(short_description, '')) LIKE '%ct%'
      OR LOWER(COALESCE(short_description, '')) LIKE '%mri%'
      OR LOWER(COALESCE(short_description, '')) LIKE '%magnetic%'
    )
  GROUP BY hadm_id
),

proc_icd_imaging AS (
  SELECT
    p.hadm_id,
    COUNT(*) AS proc_icd_ct_mri_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON p.icd_code = dp.icd_code
    AND p.icd_version = dp.icd_version
  WHERE
    (
      LOWER(COALESCE(dp.long_title, '')) LIKE '%ct%'
      OR LOWER(COALESCE(dp.long_title, '')) LIKE '%mri%'
      OR LOWER(COALESCE(dp.long_title, '')) LIKE '%magnetic%'
    )
  GROUP BY p.hadm_id
),

icu_proc_imaging AS (
  SELECT
    pe.hadm_id,
    COUNT(*) AS icu_proc_ct_mri_count
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  WHERE
    (
      LOWER(COALESCE(SAFE_CAST(pe.value AS STRING), '')) LIKE '%ct%'
      OR LOWER(COALESCE(SAFE_CAST(pe.value AS STRING), '')) LIKE '%mri%'
      OR LOWER(COALESCE(SAFE_CAST(pe.value AS STRING), '')) LIKE '%magnetic%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%ct%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%mri%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%magnetic%'
    )
  GROUP BY pe.hadm_id
),

imaging_per_admission AS (
  SELECT
    c.hadm_id,
    c.subject_id,
    c.los_days,
    c.icu_flag,
    COALESCE(h.hcpc_ct_mri_count, 0) +
    COALESCE(pi.proc_icd_ct_mri_count, 0) +
    COALESCE(ip.icu_proc_ct_mri_count, 0) AS imaging_count
  FROM cohort c
  LEFT JOIN hcpc_imaging h ON c.hadm_id = h.hadm_id
  LEFT JOIN proc_icd_imaging pi ON c.hadm_id = pi.hadm_id
  LEFT JOIN icu_proc_imaging ip ON c.hadm_id = ip.hadm_id
)

SELECT
  CASE WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days' ELSE '5-8 days' END AS los_bucket,
  icu_flag,
  COUNT(*) AS n_admissions,
  ROUND(AVG(imaging_count), 3) AS mean_ct_mri_per_admission,
  MIN(imaging_count) AS min_ct_mri_per_admission,
  MAX(imaging_count) AS max_ct_mri_per_admission
FROM imaging_per_admission
GROUP BY los_bucket, icu_flag
ORDER BY los_bucket, icu_flag;