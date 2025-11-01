WITH cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE a.hadm_id = diag.hadm_id
        AND (
          (diag.icd_version = 9 AND diag.icd_code LIKE '435%')
          OR (diag.icd_version = 10 AND diag.icd_code LIKE 'G45%')
        )
    )
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),

icu_flag AS (
  SELECT 
    hadm_id,
    CASE WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_icu.icustays` icu 
        WHERE cohort.hadm_id = icu.hadm_id
      ) THEN 'ICU' 
      ELSE 'No ICU' 
    END AS icu_use
  FROM cohort
),

imaging_events AS (
  SELECT hadm_id, 1 AS dummy
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dicd
    ON proc.icd_code = dicd.icd_code 
    AND proc.icd_version = dicd.icd_version
  WHERE 
    LOWER(dicd.long_title) LIKE '%ct%'
    OR LOWER(dicd.long_title) LIKE '%mri%'
    OR LOWER(dicd.long_title) LIKE '%computed tomography%'
    OR LOWER(dicd.long_title) LIKE '%magnetic resonance imaging%'

  UNION ALL

  SELECT hadm_id, 1 AS dummy
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` hcpc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh
    ON hcpc.hcpcs_cd = dh.code
  WHERE 
    LOWER(dh.long_description) LIKE '%ct%'
    OR LOWER(dh.long_description) LIKE '%mri%'
    OR LOWER(dh.long_description) LIKE '%computed tomography%'
    OR LOWER(dh.long_description) LIKE '%magnetic resonance imaging%'
    OR LOWER(dh.short_description) LIKE '%ct%'
    OR LOWER(dh.short_description) LIKE '%mri%'
),

imaging_counts AS (
  SELECT 
    c.hadm_id,
    COALESCE(COUNT(ie.hadm_id), 0) AS num_imaging
  FROM cohort c
  LEFT JOIN imaging_events ie
    ON c.hadm_id = ie.hadm_id
  GROUP BY c.hadm_id
),

cohort_with_meta AS (
  SELECT 
    c.hadm_id,
    c.los_days,
    IF(c.los_days <= 3, '1-3 days', '4-7 days') AS los_group,
    icf.icu_use,
    ic.num_imaging
  FROM cohort c
  INNER JOIN icu_flag icf
    ON c.hadm_id = icf.hadm_id
  INNER JOIN imaging_counts ic
    ON c.hadm_id = ic.hadm_id
)

SELECT 
  los_group,
  icu_use,
  ROUND(quantiles[OFFSET(2)]) AS median_imaging_count,
  ROUND(quantiles[OFFSET(1)]) AS q1,
  ROUND(quantiles[OFFSET(3)]) AS q3,
  FORMAT('%d (%d - %d)', 
    CAST(ROUND(quantiles[OFFSET(2)]) AS INT64), 
    CAST(ROUND(quantiles[OFFSET(1)]) AS INT64), 
    CAST(ROUND(quantiles[OFFSET(3)]) AS INT64)
  ) AS median_iqr
FROM (
  SELECT 
    los_group,
    icu_use,
    APPROX_QUANTILES(num_imaging, 4) AS quantiles
  FROM cohort_with_meta
  GROUP BY los_group, icu_use
)
ORDER BY los_group, icu_use;