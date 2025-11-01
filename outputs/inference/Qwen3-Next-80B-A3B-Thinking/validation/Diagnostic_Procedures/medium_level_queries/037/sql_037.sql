WITH patients_ami AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE d.hadm_id = a.hadm_id
          AND d.seq_num = 1
          AND (
            (d.icd_version = 10 AND d.icd_code LIKE 'I21%')
            OR (d.icd_version = 9 AND d.icd_code LIKE '410%')
          )
      ) THEN 'primary'
      ELSE 'secondary'
    END AS amitype
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 AND d.icd_code LIKE 'I21%')
          OR (d.icd_version = 9 AND d.icd_code LIKE '410%')
        )
    )
),
imaging_counts AS (
  SELECT
    h.hadm_id,
    COUNT(*) AS imaging_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d ON h.hcpcs_cd = d.code
  WHERE d.short_description LIKE '%CT%'
     OR d.short_description LIKE '%X-ray%'
     OR d.short_description LIKE '%radiograph%'
     OR d.short_description LIKE '%imaging%'
  GROUP BY h.hadm_id
),
combined AS (
  SELECT
    p.hadm_id,
    p.amitype,
    DATE_DIFF(p.dischtime, p.admittime, DAY) AS los_days,
    COALESCE(i.imaging_count, 0) AS imaging_count
  FROM patients_ami p
  LEFT JOIN imaging_counts i ON p.hadm_id = i.hadm_id
)
SELECT
  CASE
    WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
  END AS los_group,
  amitype,
  APPROX_QUANTILES(imaging_count, 4)[OFFSET(2)] AS median,
  APPROX_QUANTILES(imaging_count, 4)[OFFSET(3)] - APPROX_QUANTILES(imaging_count, 4)[OFFSET(1)] AS iqr
FROM combined
WHERE los_days BETWEEN 1 AND 7
GROUP BY los_group, amitype;