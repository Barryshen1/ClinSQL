WITH pancreatitis_base AS (
  SELECT
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.hadm_id = a.hadm_id AND di.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS pancre_diag
    ON pancre_diag.icd_code = di.icd_code AND pancre_diag.icd_version = di.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 42 AND 52
    AND LOWER(pancre_diag.long_title) LIKE '%pancreatitis%'
),
diag_proc_counts AS (
  SELECT
    pb.hadm_id,
    SUM(CASE WHEN LOWER(ld.long_title) LIKE '%diagnostic%' THEN 1 ELSE 0 END) AS diag_procs
  FROM pancreatitis_base pb
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pi
    ON pi.hadm_id = pb.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS ld
    ON ld.icd_code = pi.icd_code AND ld.icd_version = pi.icd_version
  GROUP BY pb.hadm_id
)
SELECT
  CASE
    WHEN pb.los_days BETWEEN 1 AND 4 THEN '1-4'
    WHEN pb.los_days BETWEEN 5 AND 7 THEN '5-7'
  END AS los_group,
  COUNT(*) AS num_admissions,
  AVG(COALESCE(dc.diag_procs, 0)) AS mean_diag_procs,
  MIN(COALESCE(dc.diag_procs, 0)) AS min_diag_procs,
  MAX(COALESCE(dc.diag_procs, 0)) AS max_diag_procs
FROM pancreatitis_base pb
LEFT JOIN diag_proc_counts dc ON dc.hadm_id = pb.hadm_id
WHERE pb.los_days BETWEEN 1 AND 7
GROUP BY los_group
ORDER BY los_group;