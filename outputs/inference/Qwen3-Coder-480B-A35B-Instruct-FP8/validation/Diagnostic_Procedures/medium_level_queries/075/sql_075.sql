WITH admissions_with_los AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
),
filtered_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 59 AND 69
),
diagnostic_procedures AS (
  SELECT
    di.icd_code,
    di.icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
  WHERE
    di.long_title LIKE '%diagnostic%' OR di.long_title LIKE '%procedure%'
),
admission_procedure_counts AS (
  SELECT
    a.hadm_id,
    CASE
      WHEN a.los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN a.los_days BETWEEN 4 AND 7 THEN '4-7 days'
      ELSE 'Other'
    END AS los_group,
    CASE
      WHEN d.seq_num = 1 THEN 'Primary'
      ELSE 'Secondary'
    END AS diagnosis_priority,
    COUNT(*) AS procedure_count
  FROM
    admissions_with_los a
  JOIN
    filtered_patients p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN
    diagnostic_procedures dp
    ON d.icd_code = dp.icd_code AND d.icd_version = dp.icd_version
  WHERE
    a.los_days BETWEEN 1 AND 7
  GROUP BY
    a.hadm_id, los_group, diagnosis_priority
)
SELECT
  los_group,
  diagnosis_priority,
  APPROX_QUANTILES(procedure_count, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(procedure_count, 100)[OFFSET(50)] AS p50,
  APPROX_QUANTILES(procedure_count, 100)[OFFSET(75)] AS p75
FROM
  admission_procedure_counts
GROUP BY
  los_group, diagnosis_priority
ORDER BY
  los_group, diagnosis_priority;