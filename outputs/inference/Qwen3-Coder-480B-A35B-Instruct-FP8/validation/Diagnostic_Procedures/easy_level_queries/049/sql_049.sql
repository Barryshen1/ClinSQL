WITH eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 81 AND 91
),

ecg_telemetry_proc_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE LOWER(long_title) LIKE '%ecg%' OR LOWER(long_title) LIKE '%telemetry%'
),

proc_per_admission AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    COUNT(DISTINCT pr.icd_code) AS distinct_proc_count
  FROM eligible_patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON a.hadm_id = pr.hadm_id
  INNER JOIN ecg_telemetry_proc_codes ect
    ON pr.icd_code = ect.icd_code AND pr.icd_version = ect.icd_version
  GROUP BY p.subject_id, a.hadm_id
),

proc_per_patient AS (
  SELECT
    subject_id,
    SUM(distinct_proc_count) AS total_distinct_procs
  FROM proc_per_admission
  GROUP BY subject_id
)

SELECT
  STDDEV(total_distinct_procs) AS stddev_distinct_ecg_telemetry_procs
FROM proc_per_patient;