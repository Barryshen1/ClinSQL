WITH index_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id AND d.seq_num = 1
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 65 AND 75
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'Emergency Department'
    AND d_icd.long_title LIKE '%acute respiratory failure%'
    AND a.deathtime IS NULL
    AND a.dischtime IS NOT NULL
),
readmission_flag AS (
  SELECT
    ia.*,
    CASE WHEN r.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS is_readmitted
  FROM
    index_admissions ia
  LEFT JOIN
    physionet-data.mimiciv_3_1_hosp.admissions r
    ON ia.subject_id = r.subject_id
    AND r.admittime > ia.dischtime
    AND r.admittime <= DATE_ADD(ia.dischtime, INTERVAL 30 DAY)
)
SELECT
  AVG(is_readmitted) AS readmission_rate,
  (SELECT PERCENTILE_CONT(los, 0.5) FROM readmission_flag WHERE is_readmitted = 1) AS median_los_readmitted,
  (SELECT PERCENTILE_CONT(los, 0.5) FROM readmission_flag WHERE is_readmitted = 0) AS median_los_nonreadmitted,
  AVG(CASE WHEN los > 9 THEN 1.0 ELSE 0.0 END) * 100 AS percent_los_greater_than_9_days
FROM
  readmission_flag;