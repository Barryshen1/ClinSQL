WITH
  -- Step 1: Identify hospital admissions for female patients aged 75-85
  female_patients_75_85 AS (
    SELECT
      p.subject_id,
      adm.hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      ON p.subject_id = adm.subject_id
    WHERE
      p.gender = 'F'
      AND (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year + p.anchor_age) BETWEEN 75 AND 85
  ),

  -- Step 2: Consolidate all ECG/Telemetry procedures from various sources
  ecg_procedures AS (
    -- Source 1: ICD-coded procedures
    SELECT
      subject_id,
      hadm_id,
      icd_code AS procedure_identifier
    FROM
      `physionet-data.mimiciv_3_1_hosp.procedures_icd`
    WHERE
      icd_code = '8952' -- ICD-9 code for 'Electrocardiogram'

    UNION ALL

    -- Source 2: HCPCS-coded procedures
    SELECT
      subject_id,
      hadm_id,
      hcpcs_cd AS procedure_identifier
    FROM
      `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
    WHERE
      hcpcs_cd IN (
        '93000', -- ECG, routine
        '93005', -- ECG, tracing only
        '93010', -- ECG, interpretation and report only
        '93040', -- Rhythm ECG, 1-3 leads
        '93041', -- Rhythm ECG, tracing only
        '93042', -- Rhythm ECG, interpretation and report only
        '93224', -- Ambulatory ECG monitoring up to 48 hours
        '93225', -- ... scanning analysis with report
        '93226', -- ... recording (includes hook-up, recording, and disconnection)
        '93227'  -- ... physician review and interpretation
      )

    UNION ALL

    -- Source 3: ICU procedure events
    SELECT
      subject_id,
      hadm_id,
      CAST(itemid AS STRING) AS procedure_identifier
    FROM
      `physionet-data.mimiciv_3_1_icu.procedureevents`
    WHERE
      itemid IN (
        224345, -- 12 Lead EKG
        226482  -- Telemetry
      )
  ),

  -- Step 3: Count the number of distinct procedures for each hospitalization in the cohort
  proc_counts_per_hosp AS (
    SELECT
      cohort.hadm_id,
      COUNT(DISTINCT procs.procedure_identifier) AS num_distinct_procedures
    FROM
      female_patients_75_85 AS cohort
    LEFT JOIN
      ecg_procedures AS procs
      ON cohort.hadm_id = procs.hadm_id
    GROUP BY
      cohort.hadm_id
  )

-- Step 4: Calculate the 75th percentile of the distinct procedure counts
SELECT
  APPROX_QUANTILES(num_distinct_procedures, 100)[OFFSET(75)] AS p75_distinct_ecg_procedures
FROM
  proc_counts_per_hosp;