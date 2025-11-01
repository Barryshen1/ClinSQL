WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.admission_location,
    a.insurance,
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
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON
    d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 50 AND 60
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'EMERGENCY ROOM'
    AND d.seq_num = 1
    AND dd.icd_code IN ('4590', 'K922')
),

index_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    los_days,
    hospital_expire_flag
  FROM (
    SELECT *,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
    FROM cohort
  ) t
  WHERE rn = 1
),

readmissions AS (
  SELECT
    ia.subject_id,
    ia.hadm_id AS index_hadm_id,
    ia.los_days AS index_los,
    CASE WHEN ra.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS is_readmitted
  FROM
    index_admissions ia
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` ra
  ON
    ia.subject_id = ra.subject_id
    AND ra.admittime > ia.dischtime
    AND ra.admittime <= DATETIME_ADD(ia.dischtime, INTERVAL 30 DAY)
    AND ra.hadm_id != ia.hadm_id
),

readmit_stats AS (
  SELECT
    is_readmitted,
    index_los
  FROM readmissions
)

SELECT
  ROUND(COUNTIF(is_readmitted = 1) * 100.0 / COUNT(*), 2) AS readmission_rate_percent,
  APPROX_QUANTILES(IF(is_readmitted = 1, index_los, NULL), 2)[OFFSET(1)] AS median_los_readmitted,
  APPROX_QUANTILES(IF(is_readmitted = 0, index_los, NULL), 2)[OFFSET(1)] AS median_los_not_readmitted,
  ROUND(AVG(CASE WHEN is_readmitted = 1 THEN IF(index_los > 6, 1, 0) ELSE NULL END) * 100, 2) AS percent_readmitted_with_los_gt_6,
  ROUND(AVG(CASE WHEN is_readmitted = 0 THEN IF(index_los > 6, 1, 0) ELSE NULL END) * 100, 2) AS percent_not_readmitted_with_los_gt_6
FROM readmit_stats;