WITH
  -- Step 1: Define the patient cohort of males aged 57-67
  patient_cohort AS (
    SELECT
      p.subject_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
    WHERE
      p.gender = 'M'
      AND p.anchor_age BETWEEN 57 AND 67
  ),
  -- Step 2: Find all echocardiography events from both ICD and HCPCS billing codes
  all_echo_events AS (
    -- ICD coded procedures
    SELECT
      pi.subject_id,
      pi.icd_code AS proc_code
    FROM
      `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pi
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d_icd
      ON pi.icd_code = d_icd.icd_code AND pi.icd_version = d_icd.icd_version
    WHERE
      LOWER(d_icd.long_title) LIKE '%echocardiogra%'
    UNION ALL
    -- HCPCS coded procedures
    SELECT
      hc.subject_id,
      hc.hcpcs_cd AS proc_code
    FROM
      `physionet-data.mimiciv_3_1_hosp.hcpcsevents` AS hc
    WHERE
      LOWER(hc.short_description) LIKE '%echocardiogra%'
  ),
  -- Step 3: Count the number of distinct echo procedures for each patient who had at least one
  distinct_proc_counts AS (
    SELECT
      subject_id,
      COUNT(DISTINCT proc_code) AS num_distinct_procedures
    FROM
      all_echo_events
    GROUP BY
      subject_id
  ),
  -- Step 4: Map counts back to the full patient cohort, including patients with zero procedures
  all_patient_counts AS (
    SELECT
      cohort.subject_id,
      COALESCE(counts.num_distinct_procedures, 0) AS num_procedures
    FROM
      patient_cohort AS cohort
    LEFT JOIN
      distinct_proc_counts AS counts
      ON cohort.subject_id = counts.subject_id
  )
-- Step 5: Calculate the 75th percentile of the number of distinct echo procedures across all patients in the cohort
SELECT
  APPROX_QUANTILES(num_procedures, 100)[OFFSET(75)] AS p75_distinct_echo_procedures
FROM
  all_patient_counts;