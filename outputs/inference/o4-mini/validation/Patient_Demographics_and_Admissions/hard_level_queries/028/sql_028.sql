WITH index_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.subject_id = d.subject_id
      AND a.hadm_id = d.hadm_id
      AND d.seq_num = 1
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
      ON d.icd_code = diag.icd_code
      AND d.icd_version = diag.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 55 AND 65
    AND LOWER(a.insurance) = 'medicare'
    AND a.admission_location = 'EMERGENCY'
    AND LOWER(diag.long_title) LIKE '%cellulitis%'
),

readmissions AS (
  SELECT
    ia.*,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = ia.subject_id
        AND a2.admittime > ia.dischtime
        AND a2.admittime <= DATETIME_ADD(ia.dischtime, INTERVAL 30 DAY)
    ) AS readmit_flag
  FROM index_admissions ia
)

SELECT
  -- 30-day readmission rate
  100.0 * SUM(IF(readmit_flag, 1, 0)) / COUNT(*) AS readmission_rate_pct,
  -- Median LOS for readmitted
  APPROX_QUANTILES(IF(readmit_flag, los, NULL), 2)[OFFSET(1)] AS median_los_readmitted,
  -- Median LOS for non-readmitted
  APPROX_QUANTILES(IF(NOT readmit_flag, los, NULL), 2)[OFFSET(1)] AS median_los_non_readmitted,
  -- Percent of index stays >7 days
  100.0 * SUM(IF(los > 7, 1, 0)) / COUNT(*) AS pct_index_stays_gt_7d
FROM
  readmissions;