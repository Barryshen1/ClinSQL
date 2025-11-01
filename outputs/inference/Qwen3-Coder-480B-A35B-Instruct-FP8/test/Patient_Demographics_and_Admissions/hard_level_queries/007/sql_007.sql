WITH index_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    LEAD(a.admittime) OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS next_admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id AND d.seq_num = 1
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did
    ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 83 AND 93
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'EMERGENCY ROOM'
    AND LOWER(did.long_title) LIKE '%transient ischemic attack%'
    AND a.hospital_expire_flag = 0
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime > a.admittime
),
readmit_status AS (
  SELECT
    *,
    CASE
      WHEN next_admittime IS NOT NULL
        AND DATETIME_DIFF(next_admittime, dischtime, DAY) <= 30 THEN 1
      ELSE 0
    END AS readmitted_30d
  FROM index_admissions
)
SELECT
  -- 30-day readmission rate
  AVG(CAST(readmitted_30d AS FLOAT64)) AS readmission_rate,

  -- Median LOS for readmitted vs non-readmitted
  APPROX_QUANTILES(CASE WHEN readmitted_30d = 1 THEN los_days ELSE NULL END, 2)[OFFSET(1)] AS median_los_readmitted,
  APPROX_QUANTILES(CASE WHEN readmitted_30d = 0 THEN los_days ELSE NULL END, 2)[OFFSET(1)] AS median_los_not_readmitted,

  -- Percent of index stays >10 days
  AVG(CASE WHEN los_days > 10 THEN 1.0 ELSE 0.0 END) AS pct_stays_over_10_days
FROM readmit_status;