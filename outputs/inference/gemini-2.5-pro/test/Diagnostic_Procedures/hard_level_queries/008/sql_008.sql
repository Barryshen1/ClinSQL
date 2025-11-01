WITH ugib_hadm_ids AS (
  -- Identify hospital admissions with a diagnosis of Upper GI Bleeding
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_code IN (
    -- ICD-9 codes for UGIB
    '531.00', '531.01', '531.20', '531.21', '531.40', '531.41', '531.60', '531.61',
    '532.00', '532.01', '532.20', '532.21', '532.40', '532.41', '532.60', '532.61',
    '533.00', '533.01', '533.20', '533.21', '533.40', '533.41', '533.60', '533.61',
    '534.00', '534.01', '534.20', '534.21', '534.40', '534.41', '534.60', '534.61',
    '578.0', '578.1', '578.9', '456.0', '456.20',
    -- ICD-10 codes for UGIB
    'K25.0', 'K25.1', 'K25.2', 'K25.4', 'K25.5', 'K25.6',
    'K26.0', 'K26.1', 'K26.2', 'K26.4', 'K26.5', 'K26.6',
    'K27.0', 'K27.1', 'K27.2', 'K27.4', 'K27.5', 'K27.6',
    'K28.0', 'K28.1', 'K28.2', 'K28.4', 'K28.5', 'K28.6',
    'K29.01', 'K92.0', 'K92.1', 'K92.2', 'I85.01', 'I85.11'
  )
),

first_icu_stay AS (
  -- Build the base cohort of male patients, aged 48-58 with UGIB, selecting their first ICU stay per hospital admission.
  -- A subquery is used here because window functions like ROW_NUMBER() are not allowed in a WHERE clause.
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime,
    hospital_expire_flag,
    hospital_los
  FROM (
    SELECT
      pat.subject_id,
      adm.hadm_id,
      icu.stay_id,
      icu.intime,
      adm.hospital_expire_flag,
      DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS hospital_los,
      ROW_NUMBER() OVER (PARTITION BY adm.hadm_id ORDER BY icu.intime) as rn
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON adm.subject_id = pat.subject_id
    INNER JOIN ugib_hadm_ids
      ON adm.hadm_id = ugib_hadm_ids.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
      ON adm.hadm_id = icu.hadm_id
    WHERE
      pat.gender = 'M'
      AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 48 AND 58
  )
  WHERE rn = 1
),

proc_counts AS (
  -- Count procedures for each patient that occurred on the same calendar day as ICU admission
  SELECT
    cohort.subject_id,
    cohort.hadm_id,
    cohort.stay_id,
    cohort.hospital_los,
    cohort.hospital_expire_flag,
    COUNT(proc.icd_code) AS procedure_count
  FROM first_icu_stay AS cohort
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
    ON cohort.hadm_id = proc.hadm_id
    AND proc.chartdate = DATE(cohort.intime)
  GROUP BY
    cohort.subject_id,
    cohort.hadm_id,
    cohort.stay_id,
    cohort.hospital_los,
    cohort.hospital_expire_flag
),

quintiled_cohort AS (
  -- Stratify the cohort into quintiles based on procedure counts
  SELECT
    procedure_count,
    hospital_los,
    hospital_expire_flag,
    NTILE(5) OVER (ORDER BY procedure_count) AS procedure_quintile
  FROM proc_counts
)

-- Final aggregation and reporting
SELECT
  procedure_quintile,
  AVG(procedure_count) AS avg_procedure_count,
  AVG(hospital_los) AS avg_hospital_los_days,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS in_hospital_mortality_percent
FROM quintiled_cohort
GROUP BY procedure_quintile
ORDER BY procedure_quintile;