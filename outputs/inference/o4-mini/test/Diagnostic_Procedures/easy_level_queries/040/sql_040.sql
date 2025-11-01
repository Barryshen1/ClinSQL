WITH male51_61 AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 51 AND 61
),
ecg_procs AS (
  SELECT
    subject_id,
    hcpcs_cd
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
  WHERE
    -- CPT/HCPCS codes for ECG and telemetry are roughly 93000–93299
    hcpcs_cd BETWEEN '93000' AND '93299'
),
per_patient_counts AS (
  SELECT
    m.subject_id,
    COUNT(DISTINCT e.hcpcs_cd) AS proc_count
  FROM
    male51_61 AS m
    JOIN ecg_procs AS e
      USING(subject_id)
  GROUP BY
    m.subject_id
)
SELECT
  -- Approximate 25th percentile of distinct ECG/telemetry procedures per patient
  APPROX_QUANTILES(proc_count, 100)[OFFSET(25)] AS p25_distinct_ecg_telemetry_procs
FROM
  per_patient_counts;