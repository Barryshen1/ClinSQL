WITH hospitalization_cohort AS (
  SELECT
    adm.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    -- Calculate age at admission and filter
    AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 84 AND 94
),

-- CTE to identify relevant ICD procedure codes for echocardiography
echo_icd_codes AS (
  SELECT
    icd_code,
    icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE
    LOWER(long_title) LIKE '%echocardiogram%'
    OR LOWER(long_title) LIKE '%echocardiography%'
),

-- CTE to identify relevant HCPCS procedure codes for echocardiography
echo_hcpcs_codes AS (
  SELECT
    code
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_hcpcs`
  WHERE
    LOWER(long_description) LIKE '%echocardiogram%'
    OR LOWER(long_description) LIKE '%echocardiography%'
    OR LOWER(short_description) LIKE '%echo%'
),

-- CTE to gather all echo procedure events for the cohort from both ICD and HCPCS sources
all_echo_events AS (
  -- Events from ICD procedures
  SELECT
    proc.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
  INNER JOIN
    hospitalization_cohort AS cohort
    ON proc.hadm_id = cohort.hadm_id
  INNER JOIN
    echo_icd_codes AS codes
    ON proc.icd_code = codes.icd_code AND proc.icd_version = codes.icd_version
  
  UNION ALL
  
  -- Events from HCPCS procedures
  SELECT
    hcpcs.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` AS hcpcs
  INNER JOIN
    hospitalization_cohort AS cohort
    ON hcpcs.hadm_id = cohort.hadm_id
  INNER JOIN
    echo_hcpcs_codes AS codes
    ON hcpcs.hcpcs_cd = codes.code
),

-- CTE to count the number of echo procedures for each hospitalization
echo_counts_per_hadm AS (
  SELECT
    hadm_id,
    COUNT(*) AS num_echo_procedures
  FROM
    all_echo_events
  GROUP BY
    hadm_id
)

-- Final query to find the maximum count across all hospitalizations in the cohort
SELECT
  MAX(num_echo_procedures) AS max_echo_procedures_per_hospitalization
FROM
  echo_counts_per_hadm;