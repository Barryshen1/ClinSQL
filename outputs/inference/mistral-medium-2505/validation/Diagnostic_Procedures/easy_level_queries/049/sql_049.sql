WITH male_patients_81_91 AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 81 AND 91
),

ecg_telemetry_codes AS (
  SELECT DISTINCT
    h.hcpcs_cd
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
  ON
    h.hcpcs_cd = d.code
  WHERE
    d.short_description LIKE '%ECG%'
    OR d.short_description LIKE '%telemetry%'
    OR d.short_description LIKE '%EKG%'
),

patient_procedure_counts AS (
  SELECT
    p.subject_id,
    COUNT(DISTINCT h.hcpcs_cd) AS distinct_ecg_telemetry_procedures
  FROM
    male_patients_81_91 p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  ON
    a.hadm_id = h.hadm_id
  JOIN
    ecg_telemetry_codes e
  ON
    h.hcpcs_cd = e.hcpcs_cd
  GROUP BY
    p.subject_id
)

SELECT
  STDDEV(distinct_ecg_telemetry_procedures) AS sd_distinct_ecg_telemetry_procedures
FROM
  patient_procedure_counts;