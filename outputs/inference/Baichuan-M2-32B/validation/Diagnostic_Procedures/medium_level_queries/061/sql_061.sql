WITH eligible_patients AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 64 AND 74
),
aki_admissions AS (
  SELECT
    d.hadm_id,
    MIN(d.seq_num) AS min_seq_num
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE
    d.icd_version = 10
    AND d.icd_code IN (
      'N17.0', 'N17.1', 'N17.2', 'N17.3', 'N17.4', 'N17.5', 'N17.6', 'N17.7', 'N17.8', 'N17.9'
    )
  GROUP BY d.hadm_id
),
imaging_hcpcs AS (
  SELECT code
  FROM `physionet-data.mimiciv_3_1_hosp.d_hcpcs`
  WHERE
    long_description LIKE '%imaging%' OR
    long_description LIKE '%x-ray%' OR
    long_description LIKE '%CT%' OR
    long_description LIKE '%MRI%' OR
    long_description LIKE '%ultrasound%' OR
    long_description LIKE '%scan%' OR
    long_description LIKE '%angiogram%' OR
    long_description LIKE '%echo%'
),
imaging_counts AS (
  SELECT
    h.hadm_id,
    COUNT(*) AS imaging_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  INNER JOIN imaging_hcpcs i
    ON h.hcpcs_cd = i.code
  GROUP BY h.hadm_id
),
combined AS (
  SELECT
    ep.hadm_id,
    ep.los_days,
    CASE
      WHEN aki.min_seq_num = 1 THEN 'primary'
      ELSE 'secondary'
    END AS aki_type,
    COALESCE(ic.imaging_count, 0) AS imaging_count
  FROM eligible_patients ep
  INNER JOIN aki_admissions aki
    ON ep.hadm_id = aki.hadm_id
  LEFT JOIN imaging_counts ic
    ON ep.hadm_id = ic.hadm_id
  WHERE
    ep.los_days BETWEEN 1 AND 7
),
los_groups AS (
  SELECT
    aki_type,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
    END AS los_group,
    imaging_count
  FROM combined
)
SELECT
  aki_type,
  los_group,
  APPROX_QUANTILES(imaging_count, 4)[OFFSET(2)] AS median,
  APPROX_QUANTILES(imaging_count, 4)[OFFSET(3)] - APPROX_QUANTILES(imaging_count, 4)[OFFSET(1)] AS iqr
FROM los_groups
GROUP BY aki_type, los_group
ORDER BY aki_type, los_group;