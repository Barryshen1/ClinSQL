WITH index_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit,
    a.insurance,
    a.admission_location
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND a.insurance = 'Medicare'
    AND a.dischtime IS NOT NULL
    AND a.admission_location IN (
      'EMERGENCY ROOM ADMIT',
      'EMERGENCY ROOM',
      'ER ADMIT',
      'ER'
    )
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 76 AND 86
),
index_with_stroke AS (
  SELECT ia.*
  FROM index_admissions ia
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON ia.hadm_id = d.hadm_id
  WHERE d.seq_num = 1
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '434%')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I63%')
    )
),
index_with_metrics AS (
  SELECT
    ia.*,
    TIMESTAMP_DIFF(ia.dischtime, ia.admittime, SECOND) / (24*60*60) AS los_days,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = ia.subject_id
        AND a2.admittime > ia.dischtime
        AND a2.admittime <= TIMESTAMP_ADD(ia.dischtime, INTERVAL 30 DAY)
    ) AS readmitted_30d
  FROM index_with_stroke ia
)
SELECT
  COUNT(*) AS total_index,
  COUNTIF(readmitted_30d) / COUNT(*) AS readmission_rate,
  APPROX_QUANTILES(IF(readmitted_30d, los_days, NULL), 100 IGNORE NULLS)[OFFSET(50)] AS median_los_readmitted,
  APPROX_QUANTILES(IF(NOT readmitted_30d, los_days, NULL), 100 IGNORE NULLS)[OFFSET(50)] AS median_los_nonreadmitted,
  COUNTIF(los_days > 5) / COUNT(*) * 100 AS percent_los_gt5
FROM index_with_metrics;