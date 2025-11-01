WITH idx AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    -- Length of stay in days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- 30-day readmission flag
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` ra
      WHERE ra.subject_id = a.subject_id
        AND ra.admittime > a.dischtime
        AND ra.admittime <= TIMESTAMP_ADD(a.dischtime, INTERVAL 30 DAY)
    ) AS readmitted_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON d.hadm_id = a.hadm_id
   AND d.seq_num = 1
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON dd.icd_code = d.icd_code
   AND dd.icd_version = d.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 83 AND 93
    AND a.insurance = 'MEDICARE'
    AND a.admission_location = 'EMERGENCY'
    AND LOWER(dd.long_title) LIKE '%transient ischemic attack%'
)

SELECT
  -- 30-day readmission rate
  SAFE_DIVIDE(COUNTIF(readmitted_flag), COUNT(*)) AS readmission_rate,
  -- Median LOS for readmitted patients
  (
    SELECT
      APPROX_QUANTILES(los_days, 2)[OFFSET(1)]
    FROM idx
    WHERE readmitted_flag = TRUE
  ) AS median_los_readmitted,
  -- Median LOS for non-readmitted patients
  (
    SELECT
      APPROX_QUANTILES(los_days, 2)[OFFSET(1)]
    FROM idx
    WHERE readmitted_flag = FALSE
  ) AS median_los_non_readmitted,
  -- Percent of index stays longer than 10 days
  SAFE_DIVIDE(COUNTIF(los_days > 10), COUNT(*)) * 100 AS pct_index_stays_gt_10_days
FROM idx;