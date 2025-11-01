WITH ami_cases AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    CASE 
      WHEN diag.seq_num = 1 THEN 'Primary AMI'
      ELSE 'Secondary AMI'
    END AS ami_type
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    ON adm.subject_id = diag.subject_id
   AND adm.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dcode
    ON diag.icd_code = dcode.icd_code
   AND diag.icd_version = dcode.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 43 AND 53
    AND LOWER(dcode.long_title) LIKE '%myocardial infarction%'
),
imaging_counts AS (
  SELECT
    a.hadm_id,
    a.los_days,
    a.ami_type,
    CASE 
      WHEN a.los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN a.los_days BETWEEN 4 AND 7 THEN '4-7 days'
    END AS los_category,
    COUNT(p.hadm_id) AS imaging_count
  FROM ami_cases AS a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS p
    ON a.subject_id = p.subject_id
   AND a.hadm_id = p.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS dproc
    ON p.icd_code = dproc.icd_code
   AND p.icd_version = dproc.icd_version
  WHERE p.hadm_id IS NOT NULL
    AND (
      LOWER(dproc.long_title) LIKE '%radiography%' OR
      LOWER(dproc.long_title) LIKE '%x-ray%' OR
      LOWER(dproc.long_title) LIKE '%computed tomography%' OR
      LOWER(dproc.long_title) LIKE '%ct scan%'
    )
    AND a.los_days BETWEEN 1 AND 7
  GROUP BY a.hadm_id, a.los_days, a.ami_type, los_category
),
stats AS (
  SELECT
    los_category,
    ami_type,
    APPROX_QUANTILES(imaging_count, 4)[OFFSET(2)] AS median_cts,
    APPROX_QUANTILES(imaging_count, 4)[OFFSET(1)] AS q1_cts,
    APPROX_QUANTILES(imaging_count, 4)[OFFSET(3)] AS q3_cts
  FROM imaging_counts
  GROUP BY los_category, ami_type
)
SELECT
  los_category,
  ami_type,
  median_cts,
  q1_cts AS iqr_lower,
  q3_cts AS iqr_upper
FROM stats
ORDER BY los_category, ami_type;