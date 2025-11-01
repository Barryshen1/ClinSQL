WITH female_cohort AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 88 AND 98
),

echo_icd AS (
  -- ICD procedure codes whose description mentions echo / echocardi
  SELECT
    pr.subject_id,
    CONCAT('ICD_', pr.icd_version, '_', pr.icd_code) AS proc_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dpr
    ON pr.icd_code = dpr.icd_code
   AND pr.icd_version = dpr.icd_version
  WHERE LOWER(dpr.long_title) LIKE '%echo%'
     OR LOWER(dpr.long_title) LIKE '%echocardi%'
),

echo_hcpcs AS (
  -- HCPCS / CPT events whose description or mapped long_description mentions echo / echocardi
  SELECT
    h.subject_id,
    CONCAT('HCPCS_', h.hcpcs_cd) AS proc_code
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh
    ON h.hcpcs_cd = dh.code
  WHERE LOWER(COALESCE(h.short_description, dh.long_description, '')) LIKE '%echo%'
     OR LOWER(COALESCE(h.short_description, dh.long_description, '')) LIKE '%echocardi%'
),

-- Union distinct procedure occurrences per subject to avoid counting duplicates from source tables
echo_procs_distinct AS (
  SELECT DISTINCT subject_id, proc_code FROM echo_icd
  UNION DISTINCT
  SELECT DISTINCT subject_id, proc_code FROM echo_hcpcs
),

per_subject_counts AS (
  -- Count distinct echo procedure codes per subject; include zeros for cohort members with no matches
  SELECT
    fc.subject_id,
    COALESCE(ep.count_procs, 0) AS num_distinct_echo_procs
  FROM female_cohort fc
  LEFT JOIN (
    SELECT subject_id, COUNT(1) AS count_procs
    FROM echo_procs_distinct
    GROUP BY subject_id
  ) ep
  USING(subject_id)
)

-- Compute 25th percentile (approximate) across the cohort
SELECT
  (APPROX_QUANTILES(num_distinct_echo_procs, 4))[OFFSET(1)] AS p25_distinct_echo_procedures_per_patient
FROM per_subject_counts;