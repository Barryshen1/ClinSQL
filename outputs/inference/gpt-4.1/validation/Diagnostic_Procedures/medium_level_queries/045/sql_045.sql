WITH dvt_admissions AS (
  -- Step 1: Identify admissions for females aged 78–88 with DVT
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.anchor_age,
    pat.gender,
    adm.admittime,
    adm.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      ON adm.hadm_id = diag.hadm_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 78 AND 88
    AND (
      -- ICD-10 DVT: I82.x
      (diag.icd_version = 10 AND diag.icd_code LIKE 'I82%')
      -- ICD-9 DVT: 453.x
      OR (diag.icd_version = 9 AND diag.icd_code LIKE '453%')
    )
),
admission_los AS (
  -- Step 3: Calculate LOS and bin
  SELECT
    da.subject_id,
    da.hadm_id,
    da.anchor_age,
    da.gender,
    da.admittime,
    da.dischtime,
    CAST(TIMESTAMP_DIFF(da.dischtime, da.admittime, DAY) AS INT64) AS los_days,
    CASE
      WHEN TIMESTAMP_DIFF(da.dischtime, da.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4'
      WHEN TIMESTAMP_DIFF(da.dischtime, da.admittime, DAY) BETWEEN 5 AND 8 THEN '5-8'
      ELSE NULL
    END AS los_bin
  FROM
    dvt_admissions da
),
icu_status AS (
  -- Step 2: Determine ICU status
  SELECT
    al.subject_id,
    al.hadm_id,
    al.anchor_age,
    al.gender,
    al.admittime,
    al.dischtime,
    al.los_days,
    al.los_bin,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
        WHERE icu.hadm_id = al.hadm_id
      ) THEN 'ICU'
      ELSE 'No ICU'
    END AS icu_group
  FROM
    admission_los al
  WHERE
    al.los_bin IS NOT NULL
),
noninvasive_diag AS (
  -- Step 4: Count noninvasive diagnostics per admission
  SELECT
    icu_status.subject_id,
    icu_status.hadm_id,
    icu_status.los_bin,
    icu_status.icu_group,
    COUNT(proc.icd_code) AS noninvasive_diag_count
  FROM
    icu_status
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
      ON icu_status.hadm_id = proc.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dproc
      ON proc.icd_code = dproc.icd_code AND proc.icd_version = dproc.icd_version
  WHERE
    -- Only count noninvasive procedures
    (
      LOWER(dproc.long_title) LIKE '%ultrasound%'
      OR LOWER(dproc.long_title) LIKE '%ct%'
      OR LOWER(dproc.long_title) LIKE '%mri%'
      OR LOWER(dproc.long_title) LIKE '%radiology%'
      OR LOWER(dproc.long_title) LIKE '%scan%'
      OR LOWER(dproc.long_title) LIKE '%imaging%'
      OR LOWER(dproc.long_title) LIKE '%doppler%'
      OR LOWER(dproc.long_title) LIKE '%venography%'
      OR LOWER(dproc.long_title) LIKE '%angiography%'
      OR LOWER(dproc.long_title) LIKE '%x-ray%'
    )
    OR proc.icd_code IS NULL -- count zero if no procedures
  GROUP BY
    icu_status.subject_id,
    icu_status.hadm_id,
    icu_status.los_bin,
    icu_status.icu_group
),
final_summary AS (
  -- Step 5: Aggregate by ICU group and LOS bin
  SELECT
    los_bin,
    icu_group,
    COUNT(*) AS admission_count,
    ROUND(AVG(noninvasive_diag_count),2) AS mean_noninvasive_diag_per_admission
  FROM
    noninvasive_diag
  GROUP BY
    los_bin,
    icu_group
)
SELECT
  los_bin AS LOS_Bin,
  icu_group AS ICU_Status,
  admission_count AS Admission_Count,
  mean_noninvasive_diag_per_admission AS Mean_Noninvasive_Diagnostics_Per_Admission
FROM
  final_summary
ORDER BY
  los_bin,
  icu_group;