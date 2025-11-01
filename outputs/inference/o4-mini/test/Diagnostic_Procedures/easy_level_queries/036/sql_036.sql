WITH male_patients_42_52 AS (
  SELECT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 42 AND 52
),
admissions_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    male_patients_42_52 mp
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON mp.subject_id = a.subject_id
),
valve_procedures AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.icd_code
  FROM
    admissions_cohort ac
    JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
      ON ac.subject_id = pr.subject_id
     AND ac.hadm_id    = pr.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
      ON pr.icd_code    = dp.icd_code
     AND pr.icd_version = dp.icd_version
  WHERE
    LOWER(dp.long_title) LIKE '%valve%'
    AND (
      LOWER(dp.long_title) LIKE '%repair%'
      OR LOWER(dp.long_title) LIKE '%replace%'
    )
),
patient_valve_counts AS (
  SELECT
    subject_id,
    COUNT(DISTINCT icd_code) AS distinct_valve_proc_count
  FROM
    valve_procedures
  GROUP BY
    subject_id
)
SELECT
  AVG(distinct_valve_proc_count) AS avg_distinct_valve_procedures_per_patient
FROM
  patient_valve_counts;