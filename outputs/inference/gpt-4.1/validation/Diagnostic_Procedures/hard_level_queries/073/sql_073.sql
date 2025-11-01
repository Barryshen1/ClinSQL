WITH hepatic_failure_icd AS (
  -- ICD codes for hepatic failure (ICD-10: K72.*, ICD-9: 570, 572.2, etc.)
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    (icd_version = 9 AND (
      icd_code LIKE '570%' OR
      icd_code LIKE '5722%' OR
      icd_code LIKE '5723%' OR
      icd_code LIKE '5724%' OR
      icd_code LIKE '5728%'
    ))
    OR
    (icd_version = 10 AND (
      icd_code LIKE 'K72%'
    ))
),
first_icu_stays AS (
  -- Get first ICU stay per patient
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los
  FROM (
    SELECT
      subject_id,
      MIN(intime) AS first_intime
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
    GROUP BY subject_id
  ) first
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON icu.subject_id = first.subject_id
    AND icu.intime = first.first_intime
),
cohort AS (
  -- Male, age 90-100, hepatic failure on first ICU stay
  SELECT
    p.subject_id,
    p.anchor_age,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los
  FROM first_icu_stays icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON icu.hadm_id = dx.hadm_id
  JOIN hepatic_failure_icd hfi
    ON dx.icd_code = hfi.icd_code AND dx.icd_version = hfi.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
),
diagnostic_procedures AS (
  -- Diagnostic procedures in first 72h of ICU stay
  SELECT
    proc.subject_id,
    proc.hadm_id,
    proc.icd_code,
    proc.icd_version,
    proc.chartdate,
    proc.seq_num,
    proc.icd_code AS procedure_code,
    proc.icd_version AS procedure_version,
    proc.chartdate AS procedure_date,
    proc.seq_num AS procedure_seq,
    dp.long_title
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON proc.icd_code = dp.icd_code AND proc.icd_version = dp.icd_version
  WHERE
    LOWER(dp.long_title) LIKE '%diagnostic%'
),
cohort_procedure_counts AS (
  -- For each patient, count distinct diagnostic procedures in first 72h of first ICU stay
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.intime,
    c.outtime,
    c.los,
    COUNT(DISTINCT dp.icd_code) AS num_distinct_diag_procs
  FROM cohort c
  LEFT JOIN diagnostic_procedures dp
    ON c.subject_id = dp.subject_id
    AND c.hadm_id = dp.hadm_id
    AND dp.chartdate >= c.intime
    AND dp.chartdate < DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
  GROUP BY c.subject_id, c.hadm_id, c.stay_id, c.intime, c.outtime, c.los
),
cohort_with_mortality AS (
  -- Add in-hospital mortality flag
  SELECT
    cc.*,
    adm.hospital_expire_flag
  FROM cohort_procedure_counts cc
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON cc.hadm_id = adm.hadm_id
),
quartiles AS (
  -- Assign quartiles based on number of distinct diagnostic procedures
  SELECT
    *,
    NTILE(4) OVER (ORDER BY num_distinct_diag_procs) AS quartile
  FROM cohort_with_mortality
)
SELECT
  quartile,
  COUNT(*) AS num_patients,
  MIN(num_distinct_diag_procs) AS min_procs,
  MAX(num_distinct_diag_procs) AS max_procs,
  ROUND(AVG(num_distinct_diag_procs),2) AS mean_procs,
  ROUND(AVG(los),2) AS mean_los_days,
  ROUND(100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*),2) AS in_hospital_mortality_percent
FROM quartiles
GROUP BY quartile
ORDER BY quartile;