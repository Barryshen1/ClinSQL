WITH initial_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission,
    a.insurance,
    a.admission_location,
    d.long_title AS principal_diagnosis
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
    AND p.gender = 'M'
    AND a.insurance = 'Medicare'
    AND a.admission_location LIKE '%Emergency Department%'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 50 AND 60
    AND d.long_title LIKE '%gastrointestinal hemorrhage, lower%'
),
readmission_check AS (
  SELECT
    ia.*,
    CASE WHEN r.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS readmitted
  FROM
    initial_admissions ia
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` r
    ON ia.subject_id = r.subject_id
    AND r.admittime > ia.dischtime
    AND r.admittime <= DATE_ADD(ia.dischtime, INTERVAL 30 DAY)
)
SELECT
  AVG(readmitted) AS readmission_rate,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY los) FILTER (WHERE readmitted = 1) AS median_los_readmitted,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY los) FILTER (WHERE readmitted = 0) AS median_los_not_readmitted,
  SUM(CASE WHEN los > 6 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS percent_los_gt_6
FROM (
  SELECT
    *,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los
  FROM
    readmission_check
) AS los_calc;