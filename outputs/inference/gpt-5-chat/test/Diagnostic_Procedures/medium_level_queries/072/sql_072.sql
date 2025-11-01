WITH pancreatitis_patients AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    CASE WHEN d.seq_num = 1 THEN 'primary' ELSE 'secondary' END AS diagnosis_type
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dx
    ON d.icd_code = dx.icd_code
    AND d.icd_version = dx.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON d.subject_id = p.subject_id
  WHERE LOWER(dx.long_title) LIKE '%acute pancreatitis%'
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
),
los_bucket AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    CASE
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN los_days BETWEEN 5 AND 8 THEN '5-8 days'
    END AS los_group
  FROM (
    SELECT
      subject_id,
      hadm_id,
      TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  ) a
  WHERE a.los_days BETWEEN 1 AND 8
),
diagnostic_procs AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    COUNT(*) AS num_diag_procs
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON pr.icd_code = dp.icd_code
    AND pr.icd_version = dp.icd_version
  WHERE LOWER(dp.long_title) LIKE '%diagnostic%'
  GROUP BY pr.subject_id, pr.hadm_id
)
SELECT
  l.los_group,
  p.diagnosis_type,
  AVG(dp.num_diag_procs) AS mean_diag_procs,
  MIN(dp.num_diag_procs) AS min_diag_procs,
  MAX(dp.num_diag_procs) AS max_diag_procs
FROM pancreatitis_patients p
INNER JOIN los_bucket l
  ON p.subject_id = l.subject_id
  AND p.hadm_id = l.hadm_id
INNER JOIN diagnostic_procs dp
  ON p.subject_id = dp.subject_id
  AND p.hadm_id = dp.hadm_id
GROUP BY l.los_group, p.diagnosis_type
ORDER BY l.los_group, p.diagnosis_type;