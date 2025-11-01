WITH principal_hemorrhagic AS (
  -- index admissions with principal (seq_num=1) hemorrhagic stroke diagnosis
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.admission_type,
    a.admission_location,
    a.insurance,
    p.gender,
    p.anchor_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code
    AND d.icd_version = dicd.icd_version
  WHERE d.seq_num = 1
    -- text match for hemorrhagic / subarachnoid / intracerebral descriptions
    AND (
      LOWER(dicd.long_title) LIKE '%hemorrhag%' 
      OR LOWER(dicd.long_title) LIKE '%haemorrhag%'
      OR LOWER(dicd.long_title) LIKE '%subarachnoid%'
      OR LOWER(dicd.long_title) LIKE '%intracerebral%'
    )
    -- female Medicare patients aged 68-78
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
    AND LOWER(COALESCE(a.insurance, '')) LIKE '%medicare%'
    -- admitted from the ED: admission_type or admission_location heuristics
    AND (
      a.admission_type = 'EMERGENCY'
      OR LOWER(COALESCE(a.admission_location, '')) LIKE '%emergency%'
      OR LOWER(COALESCE(a.admission_location, '')) LIKE '%ed%'
    )
    -- require valid timestamps and exclude in-hospital deaths (cannot be readmitted)
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.hospital_expire_flag = 0
),

index_with_readmit AS (
  -- flag whether each index admission has any readmission within 30 days
  SELECT
    ph.*,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = ph.subject_id
        AND a2.admittime > ph.dischtime
        AND TIMESTAMP_DIFF(a2.admittime, ph.dischtime, DAY) <= 30
    ) AS has_readmit
  FROM principal_hemorrhagic ph
)

SELECT
  COUNT(*) AS n_index_admissions,
  SUM(CASE WHEN has_readmit THEN 1 ELSE 0 END) AS n_readmitted_within_30d,
  SAFE_DIVIDE(SUM(CASE WHEN has_readmit THEN 1 ELSE 0 END), COUNT(*)) AS readmission_rate_30d,  -- fraction
  -- approximate medians (50th percentile) for LOS in days
  APPROX_QUANTILES(IF(has_readmit, los_days, NULL), 100)[OFFSET(50)] AS median_los_readmitted_days,
  APPROX_QUANTILES(IF(NOT has_readmit, los_days, NULL), 100)[OFFSET(50)] AS median_los_not_readmitted_days,
  SAFE_DIVIDE(SUM(CASE WHEN los_days > 4 THEN 1 ELSE 0 END), COUNT(*)) AS fraction_los_gt_4_days  -- fraction
FROM index_with_readmit;