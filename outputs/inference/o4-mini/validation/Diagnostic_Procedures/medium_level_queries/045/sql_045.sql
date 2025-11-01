WITH dvt_admissions AS (
  -- Female patients aged 78-88 with a DVT diagnosis
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 78 AND 88
    AND LOWER(dd.long_title) LIKE '%thrombosis%'
    -- Only consider admissions with LOS between 1 and 8 days
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 8
),
diag_counts AS (
  -- Count noninvasive diagnostics per admission
  SELECT
    he.subject_id,
    he.hadm_id,
    COUNT(*) AS diag_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` he
    JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` hc
      ON he.hcpcs_cd = hc.code
  WHERE
    -- Filter for common noninvasive venous studies
    LOWER(hc.long_description) LIKE '%ultrasound%'
    OR LOWER(hc.long_description) LIKE '%duplex%'
    OR LOWER(hc.long_description) LIKE '%venous%'
  GROUP BY
    he.subject_id,
    he.hadm_id
),
cohort_with_counts AS (
  -- Combine admissions, ICU flag, LOS group, and diag counts
  SELECT
    da.subject_id,
    da.hadm_id,
    da.los,
    CASE
      WHEN ds.hadm_id IS NOT NULL THEN 'ICU'
      ELSE 'No ICU'
    END AS icu_flag,
    CASE
      WHEN da.los BETWEEN 1 AND 4 THEN '1-4'
      ELSE '5-8'
    END AS los_group,
    COALESCE(dc.diag_count, 0) AS diag_count
  FROM
    dvt_admissions da
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` ds
      ON da.hadm_id = ds.hadm_id
    LEFT JOIN diag_counts dc
      ON da.hadm_id = dc.hadm_id
)
-- Final aggregation
SELECT
  icu_flag,
  los_group,
  COUNT(*) AS admissions,
  ROUND(AVG(diag_count), 2) AS mean_noninvasive_diag_per_admission
FROM
  cohort_with_counts
GROUP BY
  icu_flag,
  los_group
ORDER BY
  icu_flag,
  los_group;