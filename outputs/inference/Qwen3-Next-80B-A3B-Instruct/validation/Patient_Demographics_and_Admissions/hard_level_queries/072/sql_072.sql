WITH index_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.gender,
    a.insurance,
    a.admission_location,
    d.long_title
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
    ON a.hadm_id = di.hadm_id AND di.seq_num = 1
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'SNF'
    AND LOWER(d.long_title) LIKE '%acute respiratory failure%'
),

readmit_flags AS (
  SELECT
    ia.subject_id,
    MAX(CASE WHEN ra.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS readmitted_30d
  FROM
    index_admissions ia
  LEFT JOIN
    physionet-data.mimiciv_3_1_hosp.admissions ra
    ON ia.subject_id = ra.subject_id
    AND ra.admittime > ia.dischtime
    AND ra.admittime <= TIMESTAMP_ADD(ia.dischtime, INTERVAL 30 DAY)
    AND ra.hadm_id != ia.hadm_id
  GROUP BY
    ia.subject_id
),

los_data AS (
  SELECT
    ia.hadm_id,
    ia.subject_id,
    DATETIME_DIFF(ia.dischtime, ia.admittime, DAY) AS los_days,
    rf.readmitted_30d
  FROM
    index_admissions ia
  INNER JOIN
    readmit_flags rf
    ON ia.subject_id = rf.subject_id
)

SELECT
  ROUND(
    100.0 * SUM(CASE WHEN readmitted_30d = 1 THEN 1 ELSE 0 END) / COUNT(*),
    2
  ) AS readmission_rate_pct,
  APPROX_QUANTILES(IF(readmitted_30d = 1, los_days, NULL), 1)[OFFSET(0)] AS median_los_readmitted,
  APPROX_QUANTILES(IF(readmitted_30d = 0, los_days, NULL), 1)[OFFSET(0)] AS median_los_not_readmitted,
  ROUND(
    100.0 * SUM(CASE WHEN los_days > 8 THEN 1 ELSE 0 END) / COUNT(*),
    2
  ) AS percent_index_stays_gt_8_days
FROM
  los_data;