WITH index_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    a.admission_location,
    d.long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.hadm_id = diag.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE
    diag.seq_num = 1
    AND d.long_title LIKE '%acute respiratory failure%'
    AND a.insurance = 'Medicare'
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 65 AND 75
    AND a.admission_location IN ('EMERGENCY ROOM ADMIT', 'EMERGENCY ROOM')
),
readmission_check AS (
  SELECT
    ia.*,
    TIMESTAMP_DIFF(ia.dischtime, ia.admittime, DAY) AS los,
    CASE WHEN r.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS readmitted
  FROM
    index_admissions ia
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` r
    ON ia.subject_id = r.subject_id
    AND r.admittime > ia.dischtime
    AND r.admittime <= DATE_ADD(ia.dischtime, INTERVAL 30 DAY)
)
SELECT
  (SUM(readmitted) * 100.0) / COUNT(*) AS readmission_rate,
  PERCENTILE_CONT(CASE WHEN readmitted = 1 THEN los END, 0.5) AS median_los_readmitted,
  PERCENTILE_CONT(CASE WHEN readmitted = 0 THEN los END, 0.5) AS median_los_non_readmitted,
  (SUM(CASE WHEN los > 9 THEN 1 ELSE 0 END) * 100.0) / COUNT(*) AS percent_los_gt_9
FROM
  readmission_check;