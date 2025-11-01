WITH PatientEchoCounts AS (
  -- Step 1: Filter for the patient cohort and count their echocardiography procedures.
  SELECT
    p.subject_id,
    COUNT(h.hcpcs_cd) AS num_echo_procedures
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` AS h
    ON p.subject_id = h.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_hcpcs` AS d
    ON h.hcpcs_cd = d.code
  WHERE
    -- Filter for female patients aged 81-91
    p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
    -- Filter for procedures that are echocardiograms
    AND LOWER(d.short_description) LIKE '%echo%'
  GROUP BY
    p.subject_id
)
-- Step 2: From the per-patient counts, find the maximum value.
SELECT
  MAX(num_echo_procedures) AS max_echo_procedures_per_patient
FROM
  PatientEchoCounts;