WITH acute_pancreatitis_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did
    ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 42 AND 52
    AND LOWER(did.long_title) LIKE '%acute pancreatitis%'
    AND a.dischtime IS NOT NULL
),
procedure_counts AS (
  SELECT
    apa.hadm_id,
    apa.los_days,
    COUNT(*) AS num_procedures
  FROM
    acute_pancreatitis_admissions apa
  LEFT JOIN
    physionet-data.mimiciv_3_1_hosp.procedures_icd pi
    ON apa.hadm_id = pi.hadm_id
  WHERE
    apa.los_days BETWEEN 1 AND 7
  GROUP BY
    apa.hadm_id, apa.los_days
),
los_groups AS (
  SELECT
    CASE
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN los_days BETWEEN 5 AND 7 THEN '5-7 days'
    END AS los_group,
    num_procedures
  FROM
    procedure_counts
)
SELECT
  los_group,
  COUNT(*) AS patient_count,
  AVG(num_procedures) AS mean_procedures,
  MIN(num_procedures) AS min_procedures,
  MAX(num_procedures) AS max_procedures
FROM
  los_groups
GROUP BY
  los_group
ORDER BY
  los_group;