WITH index_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.admission_location,
    a.insurance,
    p.anchor_age,
    p.gender,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS index_los,
    a.dischtime AS index_dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 76 AND 86
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'TRANSFER FROM HOSPITAL'
    AND d.seq_num = 1
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '410%')
      OR
      (d.icd_version = 10 AND d.icd_code LIKE 'I21%')
    )
    AND a.dischtime IS NOT NULL
    AND a.deathtime IS NULL -- Exclude deaths during index stay
),

readmissions AS (
  SELECT
    ia.*,
    CASE
      WHEN readmit.hadm_id IS NOT NULL THEN 1
      ELSE 0
    END AS is_readmitted
  FROM
    index_admissions ia
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` readmit
  ON
    ia.subject_id = readmit.subject_id
    AND readmit.admittime > ia.dischtime
    AND readmit.admittime <= DATETIME_ADD(ia.dischtime, INTERVAL 30 DAY)
    AND readmit.hadm_id != ia.hadm_id
)

SELECT
  -- 30-day readmission rate
  ROUND(
    SUM(is_readmitted) * 100.0 / COUNT(*),
    2
  ) AS readmission_rate_pct,

  -- Median LOS for readmitted vs not
  APPROX_QUANTILES(
    IF(is_readmitted = 1, index_los, NULL),
    2
  )[OFFSET(1)] AS median_los_readmitted,

  APPROX_QUANTILES(
    IF(is_readmitted = 0, index_los, NULL),
    2
  )[OFFSET(1)] AS median_los_not_readmitted,

  -- Percent of index stays > 4 days
  ROUND(
    SUM(IF(index_los > 4, 1, 0)) * 100.0 / COUNT(*),
    2
  ) AS percent_stays_over_4_days

FROM
  readmissions;