WITH cohort AS (
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
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
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
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did
  ON
    d.icd_code = did.icd_code
    AND d.icd_version = did.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 55 AND 65
    AND a.insurance = 'Medicare'
    AND LOWER(a.admission_location) LIKE '%emergency%'
    AND d.seq_num = 1
    AND LOWER(did.long_title) LIKE '%cellulitis%'
    AND a.deathtime IS NULL
    AND a.hospital_expire_flag = 0
),

first_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    los_days
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
    FROM
      cohort
  )
  WHERE
    rn = 1
),

readmissions AS (
  SELECT
    f.subject_id,
    f.hadm_id AS index_hadm_id,
    f.los_days AS index_los,
    f.dischtime AS index_dischtime,
    a2.hadm_id AS readmit_hadm_id,
    a2.admittime AS readmit_admittime,
    CASE
      WHEN a2.hadm_id IS NOT NULL
        AND DATETIME_DIFF(a2.admittime, f.dischtime, DAY) <= 30
      THEN 1
      ELSE 0
    END AS is_30day_readmit
  FROM
    first_admissions f
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a2
  ON
    f.subject_id = a2.subject_id
    AND a2.admittime > f.dischtime
    AND DATETIME_DIFF(a2.admittime, f.dischtime, DAY) <= 30
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY f.subject_id ORDER BY a2.admittime) = 1
),

summary_stats AS (
  SELECT
    is_30day_readmit,
    index_los,
    CASE WHEN index_los > 7 THEN 1 ELSE 0 END AS los_gt_7
  FROM
    readmissions
)

SELECT
  ROUND(AVG(is_30day_readmit), 4) AS readmission_rate,
  APPROX_QUANTILES(
    CASE WHEN is_30day_readmit = 1 THEN index_los ELSE NULL END, 2
  )[OFFSET(1)] AS median_los_readmit,
  APPROX_QUANTILES(
    CASE WHEN is_30day_readmit = 0 THEN index_los ELSE NULL END, 2
  )[OFFSET(1)] AS median_los_no_readmit,
  ROUND(
    AVG(los_gt_7) * 100, 2
  ) AS percent_index_stays_gt_7_days
FROM
  summary_stats;