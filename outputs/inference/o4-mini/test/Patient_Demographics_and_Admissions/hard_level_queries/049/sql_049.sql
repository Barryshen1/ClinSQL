WITH index_cohort AS (
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
     AND a.hadm_id    = d.hadm_id
     AND d.seq_num    = 1
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code    = dd.icd_code
     AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 61 AND 71
    AND a.insurance = 'Medicare'
    AND LOWER(a.admission_location) LIKE '%nurs%'
    AND LOWER(dd.long_title) LIKE '%acute kidney injury%'
),

readmissions AS (
  SELECT
    ic.*,
    CASE
      WHEN MIN(nxt.admittime) OVER (PARTITION BY ic.subject_id, ic.hadm_id) IS NOT NULL THEN 1
      ELSE 0
    END AS readmit_flag
  FROM
    index_cohort ic
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` nxt
      ON ic.subject_id = nxt.subject_id
     AND nxt.admittime > ic.dischtime
     AND nxt.admittime <= ic.dischtime + INTERVAL 30 DAY
),

metrics AS (
  SELECT
    COUNT(*) AS total_index_stays,
    SUM(readmit_flag) AS num_readmitted,
    AVG(readmit_flag) AS readmission_rate,
    -- Median LOS among readmitted
    (SELECT APPROX_QUANTILES(los, 2)[OFFSET(1)]
     FROM readmissions
     WHERE readmit_flag = 1) AS median_los_readmitted,
    -- Median LOS among non‐readmitted
    (SELECT APPROX_QUANTILES(los, 2)[OFFSET(1)]
     FROM readmissions
     WHERE readmit_flag = 0) AS median_los_non_readmitted,
    -- Percent of index stays with LOS > 6 days
    SUM(IF(los > 6, 1, 0)) / COUNT(*) AS pct_los_gt_6
  FROM
    readmissions
)

SELECT
  total_index_stays,
  num_readmitted,
  ROUND(readmission_rate, 4) AS readmission_rate,
  median_los_readmitted,
  median_los_non_readmitted,
  ROUND(pct_los_gt_6, 4) AS pct_los_gt_6
FROM
  metrics;