WITH
cohort_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE(a.admittime) AS admit_date,
    DATE(a.dischtime) AS discharge_date,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
    AND a.hadm_id IS NOT NULL
    AND a.dischtime IS NOT NULL
),

-- Identify HF diagnoses per admission via d_icd_diagnoses long_title text match
hf_diagnoses AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    d.seq_num,
    dicd.long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
  ON
    d.icd_code = dicd.icd_code
    AND d.icd_version = dicd.icd_version
  WHERE
    (
      UPPER(dicd.long_title) LIKE '%HEART FAILURE%'
      OR UPPER(dicd.long_title) LIKE '%CONGESTIVE%'
      OR UPPER(dicd.long_title) LIKE '%CARDIAC FAILURE%'
    )
),

-- Aggregate HF presence by hadm: primary if seq_num = 1, secondary if seq_num > 1
hf_by_admission AS (
  SELECT
    hadm_id,
    MAX(CASE WHEN seq_num = 1 THEN 1 ELSE 0 END) AS hf_primary_flag,
    MAX(CASE WHEN seq_num > 1 THEN 1 ELSE 0 END) AS hf_secondary_flag
  FROM
    hf_diagnoses
  GROUP BY
    hadm_id
),

-- Imaging events (CT/MRI) during the admission: hcpcsevents joined to d_hcpcs and filtered by keywords
imaging_events AS (
  SELECT
    h.hadm_id,
    h.chartdate,
    d.long_description,
    h.short_description
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
  ON
    h.hcpcs_cd = d.code
  WHERE
    (
      (d.long_description IS NOT NULL AND (
         UPPER(d.long_description) LIKE '%COMPUTED TOMOGRAPHY%'
         OR UPPER(d.long_description) LIKE '%CT SCAN%'
         OR UPPER(d.long_description) LIKE '%CAT SCAN%'
         OR UPPER(d.long_description) LIKE '%CT%'
         OR UPPER(d.long_description) LIKE '%MAGNETIC RESONANCE%'
         OR UPPER(d.long_description) LIKE '%MRI%'
       ))
      OR
      (h.short_description IS NOT NULL AND (
         UPPER(h.short_description) LIKE '%COMPUTED TOMOGRAPHY%'
         OR UPPER(h.short_description) LIKE '%CT SCAN%'
         OR UPPER(h.short_description) LIKE '%CAT SCAN%'
         OR UPPER(h.short_description) LIKE '%CT%'
         OR UPPER(h.short_description) LIKE '%MAGNETIC RESONANCE%'
         OR UPPER(h.short_description) LIKE '%MRI%'
       ))
    )
),

-- Count imaging events per admission that occur during that admission
imaging_count_by_admission AS (
  SELECT
    ca.hadm_id,
    COUNT(ie.hadm_id) AS n_imaging
  FROM
    cohort_admissions ca
  LEFT JOIN
    imaging_events ie
  ON
    ca.hadm_id = ie.hadm_id
    AND ie.chartdate BETWEEN ca.admit_date AND ca.discharge_date
  GROUP BY
    ca.hadm_id
)

-- Final aggregation: join cohort admissions -> HF classification -> imaging counts
SELECT
  CASE
    WHEN h.hf_primary_flag = 1 THEN 'primary'
    WHEN h.hf_primary_flag = 0 AND h.hf_secondary_flag = 1 THEN 'secondary'
    ELSE 'unknown'
  END AS hf_role,
  CASE
    WHEN ca.los_days BETWEEN 1 AND 3 THEN '1-3'
    WHEN ca.los_days BETWEEN 4 AND 7 THEN '4-7'
    ELSE NULL
  END AS los_group,
  COUNT(*) AS admission_count,
  ROUND(AVG(COALESCE(ic.n_imaging, 0)), 3) AS mean_imaging_per_admission
FROM
  cohort_admissions ca
JOIN
  hf_by_admission h
ON
  ca.hadm_id = h.hadm_id
LEFT JOIN
  imaging_count_by_admission ic
ON
  ca.hadm_id = ic.hadm_id
WHERE
  -- restrict to the two LOS groups requested
  ca.los_days BETWEEN 1 AND 7
  AND (ca.los_days BETWEEN 1 AND 3 OR ca.los_days BETWEEN 4 AND 7)
  -- ensure HF classification is primary or secondary
  AND (h.hf_primary_flag = 1 OR h.hf_secondary_flag = 1)
GROUP BY
  hf_role,
  los_group
ORDER BY
  hf_role,
  los_group;