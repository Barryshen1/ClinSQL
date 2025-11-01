WITH index_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
       AND d.seq_num = 1
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
       AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'SNF'
    AND LOWER(dd.long_title) LIKE '%acute respiratory failure%'
),
admissions_with_flag AS (
  SELECT
    ia.*,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = ia.subject_id
          AND a2.admittime > ia.dischtime
          AND a2.admittime <= ia.dischtime + INTERVAL 30 DAY
      ) THEN 1
      ELSE 0
    END AS readmitted
  FROM
    index_admissions ia
)
SELECT
  -- 30-day readmission rate, safely dividing to avoid zero-denominator errors
  ROUND(100.0 * SAFE_DIVIDE(SUM(readmitted), COUNT(*)), 2) AS readmission_rate_pct,
  -- Median LOS for those readmitted
  (SELECT APPROX_QUANTILES(los, 2)[OFFSET(1)]
   FROM admissions_with_flag
   WHERE readmitted = 1) AS median_los_readmitted,
  -- Median LOS for those not readmitted
  (SELECT APPROX_QUANTILES(los, 2)[OFFSET(1)]
   FROM admissions_with_flag
   WHERE readmitted = 0) AS median_los_not_readmitted,
  -- Percent of index stays with LOS > 8 days
  ROUND(100.0 * SAFE_DIVIDE(COUNTIF(los > 8), COUNT(*)), 2) AS pct_los_gt_8_days
FROM
  admissions_with_flag;