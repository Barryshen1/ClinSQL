WITH tia_admissions AS (
  -- Get admissions for women aged 88-98 with TIA
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.gender
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
    JOIN physionet-data.mimiciv_3_1_hosp.patients p
      ON a.subject_id = p.subject_id
    JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
      ON a.hadm_id = d.hadm_id
    JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
    AND (
      -- ICD-10 TIA: G45.x
      (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^G45'))
      -- ICD-9 TIA: 435.x
      OR (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^435'))
    )
),
admission_los AS (
  -- Calculate LOS and bin
  SELECT
    ta.subject_id,
    ta.hadm_id,
    ta.admittime,
    ta.dischtime,
    IFNULL(
      SAFE_CAST(TIMESTAMP_DIFF(ta.dischtime, ta.admittime, DAY) AS INT64),
      NULL
    ) AS los_days
  FROM tia_admissions ta
),
los_binned AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    los_days,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
      ELSE NULL
    END AS los_bin
  FROM admission_los
  WHERE los_days BETWEEN 1 AND 7
),
icu_flag AS (
  -- ICU use per admission
  SELECT
    hadm_id,
    COUNT(*) AS icu_stays
  FROM physionet-data.mimiciv_3_1_icu.icustays
  GROUP BY hadm_id
),
admissions_with_icu AS (
  SELECT
    lb.subject_id,
    lb.hadm_id,
    lb.los_bin,
    IF(IFNULL(icu_flag.icu_stays, 0) > 0, 'Yes', 'No') AS icu_use
  FROM los_binned lb
  LEFT JOIN icu_flag
    ON lb.hadm_id = icu_flag.hadm_id
  WHERE lb.los_bin IS NOT NULL
),
ct_mri_procedures AS (
  -- CT/MRI procedures from procedures_icd
  SELECT
    hadm_id,
    COUNT(*) AS proc_ct_mri
  FROM physionet-data.mimiciv_3_1_hosp.procedures_icd p
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_procedures dp
    ON p.icd_code = dp.icd_code AND p.icd_version = dp.icd_version
  WHERE
    (
      -- ICD-9: CT/MRI codes (head CT: 88.91, MRI: 88.91, etc.)
      (p.icd_version = 9 AND (
        REGEXP_CONTAINS(p.icd_code, r'^88\.9[1-7]') -- CT/MRI
      ))
      -- ICD-10: B030ZZZ, B031ZZZ, etc. (brain imaging)
      OR (p.icd_version = 10 AND (
        REGEXP_CONTAINS(p.icd_code, r'^B03[0-9]ZZZ')
      ))
    )
  GROUP BY hadm_id
),
ct_mri_hcpcs AS (
  -- CT/MRI studies from hcpcsevents (CPT codes)
  SELECT
    hadm_id,
    COUNT(*) AS hcpcs_ct_mri
  FROM physionet-data.mimiciv_3_1_hosp.hcpcsevents h
  WHERE
    -- Common CPT codes for CT/MRI brain
    h.hcpcs_cd IN ('70450', '70460', '70470', '70551', '70552', '70553')
  GROUP BY hadm_id
),
ct_mri_counts AS (
  -- Sum CT/MRI counts per admission
  SELECT
    a.subject_id,
    a.hadm_id,
    a.los_bin,
    a.icu_use,
    COALESCE(p.proc_ct_mri, 0) + COALESCE(h.hcpcs_ct_mri, 0) AS ct_mri_count
  FROM admissions_with_icu a
  LEFT JOIN ct_mri_procedures p
    ON a.hadm_id = p.hadm_id
  LEFT JOIN ct_mri_hcpcs h
    ON a.hadm_id = h.hadm_id
)
SELECT
  los_bin,
  icu_use,
  APPROX_QUANTILES(ct_mri_count, 4)[OFFSET(2)] AS median_ct_mri,
  APPROX_QUANTILES(ct_mri_count, 4)[OFFSET(1)] AS iqr_ct_mri_low,
  APPROX_QUANTILES(ct_mri_count, 4)[OFFSET(3)] AS iqr_ct_mri_high,
  COUNT(*) AS n_admissions
FROM ct_mri_counts
GROUP BY los_bin, icu_use
ORDER BY los_bin, icu_use;