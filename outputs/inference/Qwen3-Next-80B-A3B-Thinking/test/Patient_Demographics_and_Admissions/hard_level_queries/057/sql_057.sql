WITH index_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_icd
    ON a.hadm_id = d_icd.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON d_icd.icd_code = d.icd_code
    AND d_icd.icd_version = d.icd_version
  WHERE
    p.gender = 'M'
    AND a.insurance = 'Medicare'
    AND p.anchor_age BETWEEN 60 AND 70
    AND a.admission_type = 'EMERGENCY'
    AND d_icd.seq_num = 1
    AND LOWER(d.long_title) LIKE '%urinary tract infection%'
    AND a.dischtime IS NOT NULL
),

readmission_status AS (
  SELECT
    ia.hadm_id,
    CASE WHEN r.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS readmitted,
    DATE_DIFF(ia.dischtime, ia.admittime, DAY) AS los
  FROM
    index_admissions ia
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` r
    ON ia.subject_id = r.subject_id
    AND r.admittime > ia.dischtime
    AND r.admittime <= DATE_ADD(ia.dischtime, INTERVAL 30 DAY)
    AND r.hadm_id != ia.hadm_id
)

SELECT
  readmitted,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY los) AS median_los,
  (SUM(CASE WHEN los > 9 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) AS percent_los_gt_9
FROM
  readmission_status
GROUP BY
  readmitted;