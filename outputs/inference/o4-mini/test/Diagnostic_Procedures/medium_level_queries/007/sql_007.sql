WITH acs_diagnoses AS (
  -- Identify ACS diagnosis codes
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code LIKE '410%' OR icd_code LIKE '411%'
),

admissions_cohort AS (
  -- Filter admissions for female patients aged 50-60 and LOS 1-8 days
  SELECT
    a.subject_id,
    a.hadm_id,
    -- Compute LOS in days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 8
),

admissions_strata AS (
  -- Assign LOS strata
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4'
      WHEN los_days BETWEEN 5 AND 8 THEN '5-8'
    END AS los_group
  FROM admissions_cohort
),

diagnosis_flags AS (
  -- Flag primary and secondary ACS diagnoses
  SELECT
    a.hadm_id,
    MAX(CASE WHEN d.seq_num = 1 AND d.icd_code IN (SELECT icd_code FROM acs_diagnoses) THEN 1 ELSE 0 END) AS has_primary_acs,
    MAX(CASE WHEN d.seq_num > 1 AND d.icd_code IN (SELECT icd_code FROM acs_diagnoses) THEN 1 ELSE 0 END) AS has_secondary_acs
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN admissions_strata a
    ON d.hadm_id = a.hadm_id
  GROUP BY a.hadm_id
),

admission_labels AS (
  -- Label admissions as primary or secondary ACS (exclude those with no ACS)
  SELECT
    h.hadm_id,
    CASE
      WHEN f.has_primary_acs = 1 THEN 'primary'
      WHEN f.has_primary_acs = 0 AND f.has_secondary_acs = 1 THEN 'secondary'
      ELSE NULL
    END AS diag_type
  FROM admissions_strata h
  JOIN diagnosis_flags f
    ON h.hadm_id = f.hadm_id
  WHERE f.has_primary_acs = 1 OR f.has_secondary_acs = 1
),

procedure_counts AS (
  -- Count diagnostic procedures per admission
  SELECT
    h.hadm_id,
    COUNT(pi.icd_code) AS proc_count
  FROM admissions_strata h
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    ON h.hadm_id = pi.hadm_id
  GROUP BY h.hadm_id
),

admission_stats AS (
  -- Combine everything
  SELECT
    s.los_group,
    l.diag_type,
    pc.proc_count
  FROM admissions_strata s
  JOIN admission_labels l
    ON s.hadm_id = l.hadm_id
  LEFT JOIN procedure_counts pc
    ON s.hadm_id = pc.hadm_id
)

-- Final aggregation: compute quartiles of procedure counts
SELECT
  los_group,
  diag_type,
  -- APPROX_QUANTILES returns an array of 5 values: [min, p25, p50, p75, max]
  QUANTILES[OFFSET(1)] AS p25_procedures,
  QUANTILES[OFFSET(2)] AS p50_procedures,
  QUANTILES[OFFSET(3)] AS p75_procedures
FROM (
  SELECT
    los_group,
    diag_type,
    APPROX_QUANTILES(proc_count, 4) AS QUANTILES
  FROM admission_stats
  GROUP BY los_group, diag_type
)
ORDER BY diag_type, los_group;