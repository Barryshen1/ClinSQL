WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    a.hospital_expire_flag
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
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON
    d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'SNF'
    AND d.seq_num = 1
    AND dd.long_title LIKE '%urinary tract infection%'
    AND a.hospital_expire_flag = 0
),

index_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    los_days
  FROM
    cohort
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) = 1
),

readmissions AS (
  SELECT
    ia.subject_id,
    ia.hadm_id AS index_hadm_id,
    ia.los_days AS index_los,
    CASE
      WHEN ra.hadm_id IS NOT NULL THEN 1
      ELSE 0
    END AS readmitted_30d
  FROM
    index_admissions ia
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` ra
  ON
    ia.subject_id = ra.subject_id
    AND ra.admittime > ia.dischtime
    AND ra.admittime <= DATETIME_ADD(ia.dischtime, INTERVAL 30 DAY)
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY ia.subject_id ORDER BY ra.admittime) = 1
)

SELECT
  -- 30-day readmission rate
  AVG(readmitted_30d) AS readmission_rate,

  -- Median LOS for readmitted vs non-readmitted
  APPROX_QUANTILES(CASE WHEN readmitted_30d = 1 THEN index_los ELSE NULL END, 2)[OFFSET(1)] AS median_los_readmitted,
  APPROX_QUANTILES(CASE WHEN readmitted_30d = 0 THEN index_los ELSE NULL END, 2)[OFFSET(1)] AS median_los_not_readmitted,

  -- Percent of stays >6 days
  AVG(CASE WHEN index_los > 6 THEN 1 ELSE 0 END) AS pct_stays_over_6_days
FROM
  readmissions;