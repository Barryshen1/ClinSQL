WITH hf_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- Flag if HF is primary (seq_num = 1) or secondary (seq_num > 1)
    MAX(CASE WHEN di.seq_num = 1 AND LOWER(dd.long_title) LIKE '%heart failure%' THEN 1 ELSE 0 END) AS is_primary_hf,
    MAX(CASE WHEN di.seq_num > 1 AND LOWER(dd.long_title) LIKE '%heart failure%' THEN 1 ELSE 0 END) AS is_secondary_hf
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 67 AND 77
    AND LOWER(dd.long_title) LIKE '%heart failure%'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
  GROUP BY a.hadm_id, a.subject_id, a.admittime, a.dischtime
),
hf_type_by_admission AS (
  SELECT
    hadm_id,
    los_days,
    CASE
      WHEN is_primary_hf = 1 THEN 'primary'
      WHEN is_secondary_hf = 1 THEN 'secondary'
      ELSE NULL
    END AS hf_type
  FROM hf_admissions
  WHERE los_days BETWEEN 1 AND 7
),
imaging_per_admission AS (
  SELECT
    h.hadm_id,
    h.los_days,
    h.hf_type,
    COUNT(*) AS imaging_count
  FROM hf_type_by_admission h
  JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` hc ON h.hadm_id = hc.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d ON hc.hcpcs_cd = d.code
  WHERE d.category = 3  -- 3 corresponds to 'Imaging' in d_hcpcs.category
  GROUP BY h.hadm_id, h.los_days, h.hf_type
),
los_grouped AS (
  SELECT
    hf_type,
    CASE
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN los_days BETWEEN 5 AND 7 THEN '5-7 days'
    END AS los_group,
    imaging_count
  FROM imaging_per_admission
  WHERE hf_type IS NOT NULL
)
SELECT
  hf_type,
  los_group,
  APPROX_QUANTILES(imaging_count, 100)[OFFSET(25)] AS p25_imaging,
  APPROX_QUANTILES(imaging_count, 100)[OFFSET(50)] AS p50_imaging,
  APPROX_QUANTILES(imaging_count, 100)[OFFSET(75)] AS p75_imaging,
  COUNT(*) AS admission_count
FROM los_grouped
GROUP BY hf_type, los_group
ORDER BY hf_type, los_group;