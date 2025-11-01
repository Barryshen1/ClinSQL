WITH male_41_51 AS (
  -- Step 1: select male patients aged between 41 and 51
  SELECT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 41 AND 51
),
ecg_telemetry_events AS (
  -- Step 2: gather all ECG/telemetry HCPCS events for those patients
  SELECT
    he.subject_id,
    he.hcpcs_cd
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` he
  JOIN
    male_41_51 m
  ON
    he.subject_id = m.subject_id
  WHERE
    -- filter on short_description containing ECG or telemetry (case-insensitive)
    (LOWER(he.short_description) LIKE '%ecg%'
     OR LOWER(he.short_description) LIKE '%telemetry%')
),
per_patient_counts AS (
  -- Step 3: count distinct procedure codes per patient
  SELECT
    subject_id,
    COUNT(DISTINCT hcpcs_cd) AS distinct_proc_count
  FROM
    ecg_telemetry_events
  GROUP BY
    subject_id
),
all_patients_with_zero AS (
  -- Step 4: ensure patients with zero events are included
  SELECT
    m.subject_id,
    COALESCE(p.distinct_proc_count, 0) AS distinct_proc_count
  FROM
    male_41_51 m
  LEFT JOIN
    per_patient_counts p
  USING (subject_id)
)
-- Step 5: compute the 75th percentile of the per-patient counts
SELECT
  APPROX_QUANTILES(distinct_proc_count, 100)[OFFSET(75)] AS percentile_75th
FROM
  all_patients_with_zero;