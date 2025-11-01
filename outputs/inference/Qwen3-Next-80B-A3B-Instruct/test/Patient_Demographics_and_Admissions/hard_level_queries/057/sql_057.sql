WITH index_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_location,
    p.anchor_age,
    p.gender,
    p.dod,
    a.hospital_expire_flag,
    d.long_title AS principal_diagnosis,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d_icd
    ON a.hadm_id = d_icd.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
    ON d_icd.icd_code = d.icd_code AND d_icd.icd_version = d.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 60 AND 70
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'EMERGENCY ROOM'
    AND d_icd.seq_num = 1  -- principal diagnosis
    AND (
      LOWER(d.long_title) LIKE '%urinary tract infection%'
      OR LOWER(d.long_title) LIKE '%pyelonephritis%'
      OR LOWER(d.long_title) LIKE '%cystitis%'
      OR LOWER(d.long_title) LIKE '%urethritis%'
      OR LOWER(d.long_title) LIKE '%urethral syndrome%'
    )
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
readmissions AS (
  SELECT
    ia.*,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM physionet-data.mimiciv_3_1_hosp.admissions a2
        WHERE a2.subject_id = ia.subject_id
          AND a2.hadm_id != ia.hadm_id
          AND a2.admittime > ia.dischtime
          AND a2.admittime <= DATE_ADD(ia.dischtime, INTERVAL 30 DAY)
          AND a2.admittime IS NOT NULL
      ) THEN 1
      ELSE 0
    END AS readmitted_30d
  FROM
    index_admissions ia
)
SELECT
  AVG(readmitted_30d) AS readmission_rate_30d,
  PERCENTILE_CONT(CASE WHEN readmitted_30d = 1 THEN los_days END, 0.5) AS median_los_readmitted,
  PERCENTILE_CONT(CASE WHEN readmitted_30d = 0 THEN los_days END, 0.5) AS median_los_non_readmitted,
  AVG(CASE WHEN los_days > 9 AND readmitted_30d = 1 THEN 1.0 ELSE 0 END) * 100 AS pct_los_gt_9_readmitted,
  AVG(CASE WHEN los_days > 9 AND readmitted_30d = 0 THEN 1.0 ELSE 0 END) * 100 AS pct_los_gt_9_non_readmitted
FROM
  readmissions;