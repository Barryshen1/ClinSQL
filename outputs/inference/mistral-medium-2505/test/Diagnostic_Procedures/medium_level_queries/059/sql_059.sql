WITH
-- Get male patients aged 67-77
eligible_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 67 AND 77
),

-- Get HF admissions with LOS categorization
hf_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    -- Calculate LOS in days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- Categorize LOS
    CASE
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 5 AND 7 THEN '5-7 days'
      ELSE NULL
    END AS los_category,
    -- Get HF diagnosis info
    d.seq_num,
    d.icd_code,
    -- Determine if HF is primary (seq_num = 1) or secondary
    CASE
      WHEN d.seq_num = 1 THEN 'Primary HF'
      ELSE 'Secondary HF'
    END AS hf_type
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    eligible_patients p ON a.subject_id = p.subject_id
  WHERE
    -- ICD-10 codes for heart failure (I50.*)
    (d.icd_code LIKE 'I50%' OR d.icd_code LIKE 'I50.%')
    AND d.icd_version = 10
    AND a.hospital_expire_flag = 0  -- Exclude patients who died in hospital
),

-- Count imaging studies per admission
imaging_counts AS (
  SELECT
    h.hadm_id,
    h.los_category,
    h.hf_type,
    COUNT(DISTINCT hc.hcpcs_cd) AS imaging_study_count
  FROM
    hf_admissions h
  JOIN
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` hc
    ON h.hadm_id = hc.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh
    ON hc.hcpcs_cd = dh.code
  WHERE
    -- Filter for imaging studies (Radiology category) with explicit cast
    CAST(dh.category AS STRING) = 'Radiology'
  GROUP BY
    h.hadm_id, h.los_category, h.hf_type
)

-- Calculate percentiles by LOS category and HF type
SELECT
  los_category,
  hf_type,
  APPROX_QUANTILES(imaging_study_count, 4)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(imaging_study_count, 4)[OFFSET(2)] AS p50,
  APPROX_QUANTILES(imaging_study_count, 4)[OFFSET(3)] AS p75
FROM
  imaging_counts
GROUP BY
  los_category, hf_type
ORDER BY
  los_category, hf_type;