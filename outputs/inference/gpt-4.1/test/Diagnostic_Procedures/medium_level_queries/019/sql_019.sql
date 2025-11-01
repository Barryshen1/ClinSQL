WITH acute_pancreatitis_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    EXTRACT(DAY FROM adm.dischtime - adm.admittime) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      ON adm.hadm_id = diag.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
      ON diag.icd_code = dicd.icd_code AND diag.icd_version = dicd.icd_version
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 42 AND 52
    AND (
      -- ICD-10 K85* or ICD-9 5770
      (diag.icd_version = 10 AND diag.icd_code LIKE 'K85%')
      OR (diag.icd_version = 9 AND diag.icd_code = '5770')
    )
    AND adm.dischtime > adm.admittime
),
diagnostic_procedures AS (
  SELECT
    proc.subject_id,
    proc.hadm_id,
    COUNT(DISTINCT proc.icd_code) AS num_diag_proc
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dproc
      ON proc.icd_code = dproc.icd_code AND proc.icd_version = dproc.icd_version
  WHERE
    LOWER(dproc.long_title) LIKE '%diagnostic%'
  GROUP BY
    proc.subject_id, proc.hadm_id
),
admission_diag_proc AS (
  SELECT
    apa.subject_id,
    apa.hadm_id,
    apa.los_days,
    CASE
      WHEN apa.los_days BETWEEN 1 AND 4 THEN 'LOS 1-4 days'
      WHEN apa.los_days BETWEEN 5 AND 7 THEN 'LOS 5-7 days'
      ELSE NULL
    END AS los_group,
    COALESCE(dp.num_diag_proc, 0) AS num_diag_proc
  FROM
    acute_pancreatitis_admissions apa
    LEFT JOIN diagnostic_procedures dp
      ON apa.subject_id = dp.subject_id AND apa.hadm_id = dp.hadm_id
  WHERE
    apa.los_days BETWEEN 1 AND 7
    AND (
      apa.los_days BETWEEN 1 AND 4
      OR apa.los_days BETWEEN 5 AND 7
    )
)
SELECT
  los_group,
  COUNT(*) AS patient_count,
  ROUND(AVG(num_diag_proc),2) AS mean_diag_proc,
  MIN(num_diag_proc) AS min_diag_proc,
  MAX(num_diag_proc) AS max_diag_proc
FROM
  admission_diag_proc
WHERE
  los_group IS NOT NULL
GROUP BY
  los_group
ORDER BY
  los_group;