WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    -- LOS in days (fractional)
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code
   AND d.icd_version = dicd.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    d.seq_num = 1  -- primary diagnosis
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) >= 0
    -- text-based filter for ischemic stroke / infarction in diagnosis description
    AND (
      LOWER(dicd.long_title) LIKE '%ischemi%'
      OR LOWER(dicd.long_title) LIKE '%infarct%'
      OR LOWER(dicd.long_title) LIKE '%cerebral infarction%'
    )
)

SELECT
  COUNT(*) AS n_admissions,
  ROUND(
    APPROX_QUANTILES(los_days, 100)[OFFSET(25)],
    2
  ) AS p25_los_days
FROM cohort;