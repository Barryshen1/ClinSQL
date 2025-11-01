WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id AS index_hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS index_los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 55 AND 65
    AND a.insurance = 'Medicare'
    AND LOWER(a.admission_location) LIKE '%emergency%'
    AND d.seq_num = 1
    AND LOWER(dd.long_title) LIKE '%cellulitis%'
),
readmission_check AS (
  SELECT
    c.subject_id,
    c.index_hadm_id,
    c.admittime,
    c.dischtime,
    c.index_los,
    CASE WHEN COUNT(r.hadm_id) > 0 THEN 1 ELSE 0 END AS readmit_30d
  FROM
    cohort c
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` r
    ON r.subject_id = c.subject_id
    AND r.hadm_id != c.index_hadm_id
    AND r.admittime > c.dischtime
    AND r.admittime <= DATETIME_ADD(c.dischtime, INTERVAL 30 DAY)
  GROUP BY
    c.subject_id, c.index_hadm_id, c.admittime, c.dischtime, c.index_los
),
summary AS (
  SELECT
    COUNT(*) AS total_index_admissions,
    SUM(readmit_30d) AS total_readmitted,
    SAFE_DIVIDE(SUM(readmit_30d), COUNT(*)) * 100 AS readmission_rate_percent,
    APPROX_QUANTILES(index_los, 100)[50] AS median_los_overall,
    APPROX_QUANTILES(IF(readmit_30d=1, index_los, NULL), 100)[50] AS median_los_readmitted,
    APPROX_QUANTILES(IF(readmit_30d=0, index_los, NULL), 100)[50] AS median_los_nonreadmitted,
    SAFE_DIVIDE(COUNTIF(index_los > 7), COUNT(*)) * 100 AS percent_los_gt_7
  FROM
    readmission_check
)
SELECT * FROM summary;