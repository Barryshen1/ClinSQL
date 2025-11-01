WITH target_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code
   AND d.icd_version = icd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 42 AND 52
    AND LOWER(icd.long_title) LIKE '%acute%pancreatitis%'
),
proc_counts AS (
  SELECT
    hadm_id,
    COUNT(*) AS proc_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  GROUP BY hadm_id
),
admissions_with_counts AS (
  SELECT
    ta.subject_id,
    ta.hadm_id,
    DATE_DIFF(DATE(ta.dischtime), DATE(ta.admittime), DAY) AS los,
    COALESCE(pc.proc_count, 0) AS proc_count
  FROM target_admissions ta
  LEFT JOIN proc_counts pc
    ON ta.hadm_id = pc.hadm_id
)
SELECT
  CASE
    WHEN los BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN los BETWEEN 5 AND 7 THEN '5-7 days'
  END AS los_group,
  COUNT(*) AS patient_count,
  ROUND(AVG(proc_count), 2)      AS mean_procedures,
  MIN(proc_count)                AS min_procedures,
  MAX(proc_count)                AS max_procedures
FROM admissions_with_counts
WHERE los BETWEEN 1 AND 7
GROUP BY los_group
ORDER BY los_group;