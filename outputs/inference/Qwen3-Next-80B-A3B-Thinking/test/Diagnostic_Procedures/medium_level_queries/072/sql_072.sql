WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
),
acute_pancreatitis_admissions AS (
  SELECT
    d.hadm_id,
    CASE
      WHEN MIN(d.seq_num) = 1 THEN 'primary'
      ELSE 'secondary'
    END AS diagnosis_type
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    di.long_title LIKE '%acute pancreatitis%'
  GROUP BY
    d.hadm_id
),
cohort_with_diagnosis AS (
  SELECT
    c.hadm_id,
    c.admittime,
    c.dischtime,
    ap.diagnosis_type
  FROM
    cohort c
  JOIN
    acute_pancreatitis_admissions ap
    ON c.hadm_id = ap.hadm_id
),
los_groups AS (
  SELECT
    sub.hadm_id,
    sub.diagnosis_type,
    CASE
      WHEN sub.los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN sub.los_days BETWEEN 5 AND 8 THEN '5-8 days'
    END AS los_group
  FROM (
    SELECT
      cd.hadm_id,
      cd.diagnosis_type,
      TIMESTAMP_DIFF(cd.dischtime, cd.admittime, DAY) AS los_days
    FROM
      cohort_with_diagnosis cd
  ) sub
  WHERE
    sub.los_days BETWEEN 1 AND 8
),
procedure_counts AS (
  SELECT
    hadm_id,
    COUNT(*) AS procedure_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  GROUP BY
    hadm_id
)
SELECT
  lg.los_group,
  lg.diagnosis_type,
  AVG(pc.procedure_count) AS mean_procedures,
  MIN(pc.procedure_count) AS min_procedures,
  MAX(pc.procedure_count) AS max_procedures
FROM
  los_groups lg
JOIN
  procedure_counts pc
  ON lg.hadm_id = pc.hadm_id
GROUP BY
  lg.los_group,
  lg.diagnosis_type;