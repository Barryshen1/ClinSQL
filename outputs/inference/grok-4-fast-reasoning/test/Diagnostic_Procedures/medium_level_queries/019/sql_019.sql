WITH filtered_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.anchor_year,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE diag.hadm_id = a.hadm_id
        AND (
          (diag.icd_version = 9 AND diag.icd_code = '5770')
          OR (diag.icd_version = 10 AND diag.icd_code LIKE 'K85%')
        )
    )
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 42 AND 52
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),
procedure_counts AS (
  SELECT
    hadm_id,
    COUNT(*) AS num_procs
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  GROUP BY hadm_id
)
SELECT
  CASE
    WHEN los_days <= 4 THEN '1-4'
    ELSE '5-7'
  END AS los_group,
  COUNT(DISTINCT subject_id) AS patient_count,
  AVG(COALESCE(pc.num_procs, 0)) AS mean_procs,
  MIN(COALESCE(pc.num_procs, 0)) AS min_procs,
  MAX(COALESCE(pc.num_procs, 0)) AS max_procs
FROM filtered_admissions fa
LEFT JOIN procedure_counts pc
  ON fa.hadm_id = pc.hadm_id
GROUP BY los_group
ORDER BY los_group;