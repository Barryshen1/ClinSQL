WITH admissions_with_los AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 58 AND 68
),
admission_procedure_counts AS (
  SELECT
    a.hadm_id,
    COUNT(p.icd_code) AS proc_count
  FROM
    admissions_with_los a
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  ON
    a.hadm_id = p.hadm_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
  ON
    p.icd_code = d.icd_code
    AND p.icd_version = d.icd_version
  WHERE
    LOWER(d.long_title) LIKE '%radiography%' OR LOWER(d.long_title) LIKE '%ct%'
  GROUP BY
    a.hadm_id
),
admissions_with_procs AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.los_days,
    COALESCE(ap.proc_count, 0) AS proc_count
  FROM
    admissions_with_los a
  LEFT JOIN
    admission_procedure_counts ap
  ON
    a.hadm_id = ap.hadm_id
),
grouped_stats AS (
  SELECT
    CASE
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN los_days BETWEEN 5 AND 7 THEN '5-7 days'
    END AS los_group,
    COUNT(DISTINCT subject_id) AS patient_count,
    COUNT(hadm_id) AS admission_count,
    AVG(proc_count) AS mean_procedures_per_admission
  FROM
    admissions_with_procs
  WHERE
    los_days BETWEEN 1 AND 7
  GROUP BY
    los_group
)
SELECT
  los_group,
  patient_count,
  admission_count,
  ROUND(mean_procedures_per_admission, 2) AS mean_procedures_per_admission
FROM
  grouped_stats
ORDER BY
  los_group;