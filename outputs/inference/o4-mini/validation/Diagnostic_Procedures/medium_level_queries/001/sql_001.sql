WITH
-- 1. Identify primary ACS admissions
primary_acs AS (
  SELECT
    di.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON di.icd_code = dd.icd_code
     AND di.icd_version = CAST(dd.icd_version AS INT64)
  WHERE
    LOWER(dd.long_title) LIKE '%acute coronary syndrome%'
    AND di.seq_num = 1
  GROUP BY
    di.hadm_id
),
-- 2. Identify secondary ACS admissions (ACS in seq_num>1 but not primary)
secondary_acs AS (
  SELECT
    di.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON di.icd_code = dd.icd_code
     AND di.icd_version = CAST(dd.icd_version AS INT64)
  WHERE
    LOWER(dd.long_title) LIKE '%acute coronary syndrome%'
    AND di.seq_num > 1
    AND di.hadm_id NOT IN (SELECT hadm_id FROM primary_acs)
  GROUP BY
    di.hadm_id
),
-- 3. Build cohort with stay buckets and diagnosis type
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days,
    CASE
      WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) BETWEEN 1 AND 4 THEN '1-4'
      WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) BETWEEN 5 AND 8 THEN '5-8'
      ELSE NULL
    END AS los_bucket,
    CASE
      WHEN a.hadm_id IN (SELECT hadm_id FROM primary_acs)   THEN 'Primary'
      WHEN a.hadm_id IN (SELECT hadm_id FROM secondary_acs) THEN 'Secondary'
      ELSE NULL
    END AS diag_type,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
),
-- 4. Compute radiology counts per admission
radiology_counts AS (
  SELECT
    c.hadm_id,
    COUNT(*) AS rad_count
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
      ON c.hadm_id = h.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
      ON h.hcpcs_cd = d.code
  WHERE
    c.los_bucket IS NOT NULL
    AND d.category = 'Radiology'
    AND (
      LOWER(d.short_description) LIKE '%ct%'
      OR LOWER(d.short_description) LIKE '%x-ray%'
      OR LOWER(d.long_description)  LIKE '%ct%'
      OR LOWER(d.long_description)  LIKE '%x-ray%'
    )
    AND DATE(h.chartdate) BETWEEN DATE(c.admittime) AND DATE(c.dischtime)
  GROUP BY
    c.hadm_id
)
-- 5. Final aggregation
SELECT
  c.diag_type,
  c.los_bucket,
  AVG(rc.rad_count) AS mean_radiology_count,
  MIN(rc.rad_count) AS min_radiology_count,
  MAX(rc.rad_count) AS max_radiology_count
FROM
  cohort c
  LEFT JOIN radiology_counts rc
    ON c.hadm_id = rc.hadm_id
WHERE
  c.diag_type IS NOT NULL
  AND c.los_bucket IS NOT NULL
GROUP BY
  c.diag_type,
  c.los_bucket
ORDER BY
  c.diag_type,
  c.los_bucket;