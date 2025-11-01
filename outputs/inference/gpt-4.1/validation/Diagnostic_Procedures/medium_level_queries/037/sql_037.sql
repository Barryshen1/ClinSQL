WITH ami_codes AS (
  -- List of AMI ICD codes (ICD-9 and ICD-10)
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^410|^411')) OR
    (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^I21|^I22'))
),
ami_admissions AS (
  -- Find admissions with AMI, and classify as primary/secondary
  SELECT
    d.subject_id,
    d.hadm_id,
    CASE
      WHEN MIN(CASE WHEN a.icd_code IS NOT NULL AND d.seq_num = 1 THEN 1 ELSE 0 END) = 1 THEN 'primary'
      ELSE 'secondary'
    END AS ami_type
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN ami_codes a
    ON d.icd_code = a.icd_code AND d.icd_version = a.icd_version
  GROUP BY d.subject_id, d.hadm_id
  HAVING SUM(CASE WHEN a.icd_code IS NOT NULL THEN 1 ELSE 0 END) > 0
),
target_admissions AS (
  -- Filter for males aged 43–53, join AMI admissions, calculate LOS
  SELECT
    a.subject_id,
    a.hadm_id,
    ami.ami_type,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN ami_admissions ami
    ON a.subject_id = ami.subject_id AND a.hadm_id = ami.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),
radiology_codes AS (
  -- List of procedure codes for radiography/CT
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE
    LOWER(long_title) LIKE '%radiography%'
    OR LOWER(long_title) LIKE '%ct%'
),
radiology_counts AS (
  -- Count radiography/CT procedures per admission
  SELECT
    ta.subject_id,
    ta.hadm_id,
    ta.ami_type,
    ta.los_days,
    CASE
      WHEN ta.los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN ta.los_days BETWEEN 4 AND 7 THEN '4-7'
      ELSE NULL
    END AS los_group,
    COUNT(rc.icd_code) AS num_radiology
  FROM target_admissions ta
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON ta.subject_id = pr.subject_id AND ta.hadm_id = pr.hadm_id
  LEFT JOIN radiology_codes rc
    ON pr.icd_code = rc.icd_code AND pr.icd_version = rc.icd_version
  GROUP BY ta.subject_id, ta.hadm_id, ta.ami_type, ta.los_days, los_group
),
stats AS (
  -- Compute median and IQR per group
  SELECT
    los_group,
    ami_type,
    COUNT(*) AS n_admissions,
    APPROX_QUANTILES(num_radiology, 4)[OFFSET(2)] AS median_num_radiology,
    APPROX_QUANTILES(num_radiology, 4)[OFFSET(1)] AS iqr_low,
    APPROX_QUANTILES(num_radiology, 4)[OFFSET(3)] AS iqr_high
  FROM radiology_counts
  WHERE los_group IS NOT NULL
  GROUP BY los_group, ami_type
)
SELECT
  los_group,
  ami_type,
  n_admissions,
  median_num_radiology,
  iqr_low,
  iqr_high
FROM stats
ORDER BY los_group, ami_type;