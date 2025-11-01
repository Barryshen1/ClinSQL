WITH cohort AS (
  -- All male ICU patients aged 42-52
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    pat.anchor_age,
    pat.gender
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 42 AND 52
),
ami_icd AS (
  -- ICD codes for AMI (ICD-9: 410*, ICD-10: I21*, I22*)
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    (icd_version = 9 AND icd_code LIKE '410%')
    OR (icd_version = 10 AND (icd_code LIKE 'I21%' OR icd_code LIKE 'I22%'))
),
ami_cohort AS (
  -- ICU stays with AMI diagnosis
  SELECT DISTINCT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.intime,
    c.outtime,
    c.anchor_age,
    c.gender
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON c.hadm_id = d.hadm_id
    JOIN ami_icd a
      ON d.icd_code = a.icd_code AND d.icd_version = a.icd_version
),
procedure_window AS (
  -- For each ICU stay, count distinct procedures in first 72h
  SELECT
    a.subject_id,
    a.hadm_id,
    a.stay_id,
    COUNT(DISTINCT p.icd_code) AS diagnostic_intensity
  FROM
    ami_cohort a
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
      ON a.hadm_id = p.hadm_id
      AND p.chartdate >= a.intime
      AND p.chartdate < TIMESTAMP_ADD(a.intime, INTERVAL 72 HOUR)
  GROUP BY
    a.subject_id, a.hadm_id, a.stay_id
),
ami_stats AS (
  -- LOS and mortality for AMI cohort
  SELECT
    a.subject_id,
    a.hadm_id,
    a.stay_id,
    EXTRACT(DAY FROM (adm.dischtime - adm.admittime)) +
      EXTRACT(HOUR FROM (adm.dischtime - adm.admittime))/24.0 AS hospital_los,
    adm.hospital_expire_flag
  FROM
    ami_cohort a
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
      ON a.hadm_id = adm.hadm_id
),
non_ami_cohort AS (
  -- Age-matched male ICU patients without AMI
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.intime,
    c.outtime,
    c.anchor_age,
    c.gender
  FROM
    cohort c
  WHERE
    c.hadm_id NOT IN (
      SELECT hadm_id FROM ami_cohort
    )
),
non_ami_stats AS (
  -- LOS and mortality for non-AMI cohort
  SELECT
    n.subject_id,
    n.hadm_id,
    n.stay_id,
    EXTRACT(DAY FROM (adm.dischtime - adm.admittime)) +
      EXTRACT(HOUR FROM (adm.dischtime - adm.admittime))/24.0 AS hospital_los,
    adm.hospital_expire_flag
  FROM
    non_ami_cohort n
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
      ON n.hadm_id = adm.hadm_id
)
-- Final output: 90th percentile diagnostic intensity (AMI), mean LOS and mortality for both groups
SELECT
  -- Diagnostic intensity (AMI cohort)
  PERCENTILE_CONT(diagnostic_intensity, 0.9) OVER () AS diagnostic_intensity_90th_percentile,
  -- Mean LOS and mortality (AMI cohort)
  (SELECT AVG(hospital_los) FROM ami_stats) AS mean_hospital_los_ami,
  (SELECT AVG(CAST(hospital_expire_flag AS FLOAT64)) FROM ami_stats) AS in_hospital_mortality_ami,
  -- Mean LOS and mortality (non-AMI cohort)
  (SELECT AVG(hospital_los) FROM non_ami_stats) AS mean_hospital_los_non_ami,
  (SELECT AVG(CAST(hospital_expire_flag AS FLOAT64)) FROM non_ami_stats) AS in_hospital_mortality_non_ami
FROM
  procedure_window
LIMIT 1;