WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_location,
    a.hospital_expire_flag,
    a.insurance,
    p.anchor_age,
    p.gender,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'EMERGENCY ROOM'
    AND a.hospital_expire_flag = 0
),

hemorrhagic_stroke AS (
  SELECT DISTINCT
    c.*
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    c.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON
    d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE
    d.seq_num = 1
    AND (
      (d.icd_version = 10 AND d.icd_code LIKE 'I61%')
      OR
      (d.icd_version = 10 AND d.icd_code LIKE 'I62%')
    )
),

readmissions AS (
  SELECT
    h1.subject_id,
    h1.hadm_id AS index_hadm_id,
    h1.los_days AS index_los,
    h1.dischtime AS index_dischtime,
    MIN(h2.admittime) AS next_admittime,
    DATETIME_DIFF(MIN(h2.admittime), h1.dischtime, DAY) AS days_to_readmit
  FROM
    hemorrhagic_stroke h1
  LEFT JOIN
    hemorrhagic_stroke h2
  ON
    h1.subject_id = h2.subject_id
    AND h2.admittime > h1.dischtime
    AND DATETIME_DIFF(h2.admittime, h1.dischtime, DAY) <= 30
  GROUP BY
    h1.subject_id, h1.hadm_id, h1.los_days, h1.dischtime
),

readmit_flags AS (
  SELECT
    *,
    CASE WHEN next_admittime IS NOT NULL THEN 1 ELSE 0 END AS readmitted,
    CASE WHEN index_los > 4 THEN 1 ELSE 0 END AS los_gt_4
  FROM
    readmissions
)

SELECT
  -- 30-day readmission rate
  AVG(CAST(readmitted AS FLOAT64)) AS readmission_rate,

  -- Median LOS for readmitted vs non-readmitted
  (
    SELECT
      APPROX_QUANTILES(index_los, 2)[OFFSET(1)]
    FROM
      readmit_flags
    WHERE
      readmitted = 1
  ) AS median_los_readmitted,

  (
    SELECT
      APPROX_QUANTILES(index_los, 2)[OFFSET(1)]
    FROM
      readmit_flags
    WHERE
      readmitted = 0
  ) AS median_los_not_readmitted,

  -- % with LOS > 4 days
  AVG(CAST(los_gt_4 AS FLOAT64)) AS pct_los_gt_4_days

FROM
  readmit_flags;