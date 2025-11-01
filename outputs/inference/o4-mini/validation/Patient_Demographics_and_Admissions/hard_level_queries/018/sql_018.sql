WITH cohort AS (
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
     AND a.hadm_id   = d.hadm_id
     AND d.seq_num   = 1
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code    = dd.icd_code
     AND d.icd_version = dd.icd_version
  WHERE
    p.gender          = 'F'
    AND p.anchor_age BETWEEN 58 AND 68
    AND a.admission_type = 'EMERGENCY'
    AND a.insurance      = 'Medicare'
    AND LOWER(dd.long_title) LIKE '%femoral neck fracture%'
),
readm AS (
  SELECT
    c.*,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = c.subject_id
        AND a2.admittime > c.dischtime
        AND a2.admittime <= TIMESTAMP_ADD(c.dischtime, INTERVAL 30 DAY)
    ) AS is_readmitted,
    CASE WHEN DATE_DIFF(c.dischtime, c.admittime, DAY) > 8 THEN 1 ELSE 0 END AS long_stay_flag
  FROM cohort c
)

-- Final aggregated results
SELECT
  -- Overall 30-day readmission rate
  ROUND(100.0 * SUM(CASE WHEN is_readmitted THEN 1 ELSE 0 END) / COUNT(1), 2) AS readmission_rate_pct,
  -- Median LOS if readmitted
  (SELECT APPROX_QUANTILES(los, 2)[OFFSET(1)]
   FROM readm
   WHERE is_readmitted) AS median_los_readmitted,
  -- Median LOS if NOT readmitted
  (SELECT APPROX_QUANTILES(los, 2)[OFFSET(1)]
   FROM readm
   WHERE NOT is_readmitted) AS median_los_non_readmitted,
  -- Percent of all index stays > 8 days
  ROUND(100.0 * SUM(long_stay_flag) / COUNT(1), 2) AS pct_initial_stays_gt8d
FROM
  readm;