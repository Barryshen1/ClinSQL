WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.subject_id = d.subject_id
     AND a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 76 AND 86
    AND a.insurance = 'MEDICARE'
    AND LOWER(a.admission_location) LIKE '%ed%'
    AND d.seq_num = 1
    AND (
      -- ICD-10 ischemic stroke
      (d.icd_version = 10 AND STARTS_WITH(d.icd_code, 'I63'))
      -- ICD-9 ischemic stroke codes 433.x1, 434.x1, 436
      OR (d.icd_version = 9 AND (
            d.icd_code LIKE '433.%1'
         OR d.icd_code LIKE '434.%1'
         OR d.icd_code = '436'
      ))
    )
),
readm AS (
  SELECT
    c.*,
    CASE WHEN r.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS readmitted_30d
  FROM
    cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` r
      ON c.subject_id = r.subject_id
     AND r.admittime > c.dischtime
     AND r.admittime <= TIMESTAMP_ADD(c.dischtime, INTERVAL 30 DAY)
     AND r.hadm_id != c.hadm_id
)
SELECT
  readmitted_30d,
  COUNT(*) AS n_patients,
  ROUND(100.0 * SUM(readmitted_30d) / COUNT(*), 2) AS pct_readmitted_30d,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days,
  ROUND(100.0 * COUNTIF(los_days > 5) / COUNT(*), 2) AS pct_los_gt_5d
FROM
  readm
GROUP BY
  readmitted_30d
ORDER BY
  readmitted_30d;