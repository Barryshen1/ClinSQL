WITH ecg_telemetry_procedures AS (
  SELECT
    a.hadm_id,
    COUNT(DISTINCT h.hcpcs_cd) AS num_ecg_telemetry_procedures
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.hcpcsevents h
    ON a.hadm_id = h.hadm_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.d_hcpcs d
    ON h.hcpcs_cd = d.code
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
    AND (
      LOWER(d.short_description) LIKE '%ecg%'
      OR LOWER(d.short_description) LIKE '%telemetry%'
    )
  GROUP BY
    a.hadm_id
)
SELECT
  PERCENTILE_CONT(num_ecg_telemetry_procedures, 0.75) AS p75_ecg_telemetry_procedures_per_admission
FROM
  ecg_telemetry_procedures;