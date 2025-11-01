WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    a.admission_location,
    a.insurance,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS index_los,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS admission_rank
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'SNF'
    AND a.hospital_expire_flag = 0
),

principal_diagnosis AS (
  SELECT
    d.hadm_id,
    d.icd_code,
    d.icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON
    d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE
    d.seq_num = 1
    AND LOWER(dd.long_title) LIKE '%acute respiratory failure%'
),

index_admissions AS (
  SELECT
    c.*
  FROM
    cohort c
  JOIN
    principal_diagnosis pd
  ON
    c.hadm_id = pd.hadm_id
  WHERE
    c.admission_rank = 1
),

readmissions AS (
  SELECT
    ia.subject_id,
    ia.hadm_id AS index_hadm_id,
    ia.admittime AS index_admittime,
    ia.dischtime AS index_dischtime,
    ia.index_los,
    CASE
      WHEN ra.hadm_id IS NOT NULL THEN 1
      ELSE 0
    END AS is_readmitted
  FROM
    index_admissions ia
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` ra
  ON
    ia.subject_id = ra.subject_id
    AND ra.admittime > ia.dischtime
    AND ra.admittime <= DATETIME_ADD(ia.dischtime, INTERVAL 30 DAY)
    AND ra.admission_type != 'PSYCHIATRIC'
    AND ra.hospital_expire_flag = 0
  WHERE
    ia.hospital_expire_flag = 0
),

readmit_stats AS (
  SELECT
    is_readmitted,
    index_los,
    CASE WHEN index_los > 8 THEN 1 ELSE 0 END AS los_gt_8
  FROM
    readmissions
)

SELECT
  -- Readmission rate
  AVG(CAST(is_readmitted AS FLOAT64)) AS readmission_rate,

  -- Median LOS by readmission status
  APPROX_QUANTILES(index_los, 2)[OFFSET(1)] AS median_los,

  -- Median LOS for readmitted
  (
    SELECT APPROX_QUANTILES(index_los, 2)[OFFSET(1)]
    FROM readmit_stats
    WHERE is_readmitted = 1
  ) AS median_los_readmitted,

  -- Median LOS for not readmitted
  (
    SELECT APPROX_QUANTILES(index_los, 2)[OFFSET(1)]
    FROM readmit_stats
    WHERE is_readmitted = 0
  ) AS median_los_not_readmitted,

  -- Percent index stays >8 days
  AVG(CAST(los_gt_8 AS FLOAT64)) * 100 AS percent_los_gt_8,

  -- Percent index stays >8 days for readmitted
  (
    SELECT AVG(CAST(los_gt_8 AS FLOAT64)) * 100
    FROM readmit_stats
    WHERE is_readmitted = 1
  ) AS percent_los_gt_8_readmitted,

  -- Percent index stays >8 days for not readmitted
  (
    SELECT AVG(CAST(los_gt_8 AS FLOAT64)) * 100
    FROM readmit_stats
    WHERE is_readmitted = 0
  ) AS percent_los_gt_8_not_readmitted

FROM
  readmit_stats;