WITH aki_admissions AS (
  -- Find admissions for female patients aged 64-74 with AKI diagnosis
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.anchor_age,
    pat.gender,
    adm.admittime,
    adm.dischtime,
    diag.seq_num,
    diag.icd_code,
    diag.icd_version,
    CASE
      WHEN diag.seq_num = 1 THEN 'primary'
      ELSE 'secondary'
    END AS aki_dx_type
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 64 AND 74
    AND (
      (diag.icd_version = 9 AND diag.icd_code LIKE '584%') -- AKI ICD-9
      OR
      (diag.icd_version = 10 AND diag.icd_code LIKE 'N17%') -- AKI ICD-10
    )
),

imaging_procedures AS (
  -- Identify imaging procedures per admission
  SELECT
    proc.subject_id,
    proc.hadm_id,
    COUNT(DISTINCT proc.icd_code) AS imaging_study_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dproc
    ON proc.icd_code = dproc.icd_code AND proc.icd_version = dproc.icd_version
  WHERE
    LOWER(dproc.long_title) LIKE '%imaging%'
    OR LOWER(dproc.long_title) LIKE '%radiology%'
    OR LOWER(dproc.long_title) LIKE '%ct%'
    OR LOWER(dproc.long_title) LIKE '%mri%'
    OR LOWER(dproc.long_title) LIKE '%ultrasound%'
    OR LOWER(dproc.long_title) LIKE '%x-ray%'
  GROUP BY
    proc.subject_id, proc.hadm_id
),

aki_imaging AS (
  -- Merge AKI admissions with imaging counts and LOS
  SELECT
    a.subject_id,
    a.hadm_id,
    a.anchor_age,
    a.gender,
    a.aki_dx_type,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    IFNULL(ip.imaging_study_count, 0) AS imaging_study_count
  FROM
    aki_admissions a
  LEFT JOIN
    imaging_procedures ip
    ON a.subject_id = ip.subject_id AND a.hadm_id = ip.hadm_id
  WHERE
    a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
),

aki_imaging_stratified AS (
  -- Stratify by LOS group
  SELECT
    *,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
      ELSE NULL
    END AS los_group
  FROM
    aki_imaging
  WHERE
    los_days BETWEEN 1 AND 7
)

SELECT
  los_group,
  aki_dx_type,
  APPROX_QUANTILES(imaging_study_count, 4)[OFFSET(2)] AS median_imaging_studies,
  APPROX_QUANTILES(imaging_study_count, 4)[OFFSET(1)] AS iqr_low,
  APPROX_QUANTILES(imaging_study_count, 4)[OFFSET(3)] AS iqr_high
FROM
  aki_imaging_stratified
GROUP BY
  los_group, aki_dx_type
ORDER BY
  los_group, aki_dx_type;