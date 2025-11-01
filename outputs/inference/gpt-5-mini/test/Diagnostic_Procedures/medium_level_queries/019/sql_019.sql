WITH cohort_admissions AS (
  -- Admissions for male patients age 42-52 with an acute pancreatitis diagnosis
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  USING(subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 42 AND 52
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
        ON d.icd_code = dicd.icd_code
        AND d.icd_version = dicd.icd_version
      WHERE
        d.hadm_id = a.hadm_id
        AND LOWER(dicd.long_title) LIKE '%acute pancreatitis%'
    )
),

procs_per_hadm AS (
  -- Count procedures (procedures_icd rows) per admission
  SELECT
    hadm_id,
    COUNT(*) AS num_procs
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  GROUP BY
    hadm_id
),

cohort_with_procs AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.los_days,
    COALESCE(p.num_procs, 0) AS num_procs
  FROM
    cohort_admissions c
  LEFT JOIN
    procs_per_hadm p
  USING(hadm_id)
  -- limit to LOS groups of interest (1-4 or 5-7 days)
  WHERE
    (c.los_days BETWEEN 1 AND 4)
    OR (c.los_days BETWEEN 5 AND 7)
)

SELECT
  CASE
    WHEN los_days BETWEEN 1 AND 4 THEN '1-4'
    WHEN los_days BETWEEN 5 AND 7 THEN '5-7'
    ELSE 'other'
  END AS los_group,
  COUNT(DISTINCT subject_id) AS patient_count,
  -- statistics of diagnostic procedures per admission (admissions with no procedures counted as 0)
  ROUND(AVG(num_procs), 2) AS mean_procedures_per_admission,
  MIN(num_procs) AS min_procedures_per_admission,
  MAX(num_procs) AS max_procedures_per_admission
FROM
  cohort_with_procs
GROUP BY
  los_group
ORDER BY
  -- keep the natural LOS order
  CASE los_group WHEN '1-4' THEN 1 WHEN '5-7' THEN 2 ELSE 3 END;