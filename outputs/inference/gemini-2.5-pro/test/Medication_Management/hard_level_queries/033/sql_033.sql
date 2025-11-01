WITH
-- 1. Define the cohort: Male patients aged 80-90 with a sepsis diagnosis.
cohort AS (
  SELECT DISTINCT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON adm.subject_id = p.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.hadm_id = dx.hadm_id
  WHERE
    p.gender = 'M'
    AND (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year + p.anchor_age) BETWEEN 80 AND 90
    AND (
      -- Sepsis-related ICD codes
      (dx.icd_version = 9 AND dx.icd_code IN ('99591', '99592', '78552'))
      OR (dx.icd_version = 10 AND (dx.icd_code LIKE 'A41%' OR dx.icd_code LIKE 'R652%'))
    )
),

-- 2. Get all medication administrations in the first 24h for the cohort
meds_first_24h AS (
  SELECT
    c.hadm_id,
    emar.medication
  FROM
    cohort AS c
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.emar` AS emar
    ON c.hadm_id = emar.hadm_id
  WHERE
    emar.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
    AND emar.medication IS NOT NULL
),

-- 3. Calculate Medication Complexity Score (MCS) and flag for drug types
patient_med_summary AS (
  SELECT
    meds.hadm_id,
    COUNT(DISTINCT meds.medication) AS medication_complexity_score,
    -- Flag for receiving at least one QT-prolonging drug
    MAX(CASE
      WHEN
        -- This is a non-exhaustive list of common QT-prolonging drugs
        LOWER(meds.medication) LIKE 'amiodarone%' OR
        LOWER(meds.medication) LIKE 'sotalol%' OR
        LOWER(meds.medication) LIKE 'quinidine%' OR
        LOWER(meds.medication) LIKE 'haloperidol%' OR
        LOWER(meds.medication) LIKE 'ziprasidone%' OR
        LOWER(meds.medication) LIKE 'olanzapine%' OR
        LOWER(meds.medication) LIKE 'risperidone%' OR
        LOWER(meds.medication) LIKE 'quetiapine%' OR
        LOWER(meds.medication) LIKE 'citalopram%' OR
        LOWER(meds.medication) LIKE 'escitalopram%' OR
        LOWER(meds.medication) LIKE 'erythromycin%' OR
        LOWER(meds.medication) LIKE 'clarithromycin%' OR
        LOWER(meds.medication) LIKE 'azithromycin%' OR
        LOWER(meds.medication) LIKE 'levofloxacin%' OR
        LOWER(meds.medication) LIKE 'moxifloxacin%' OR
        LOWER(meds.medication) LIKE 'ondansetron%' OR
        LOWER(meds.medication) LIKE 'methadone%'
      THEN 1 ELSE 0 END) AS on_qt_prolonging_drug,
    -- Flag for receiving at least one bleeding-risk drug
    MAX(CASE
      WHEN
        -- This is a non-exhaustive list of common bleeding-risk drugs
        -- Anticoagulants
        LOWER(meds.medication) LIKE 'warfarin%' OR
        LOWER(meds.medication) LIKE 'heparin%' OR
        LOWER(meds.medication) LIKE 'enoxaparin%' OR
        LOWER(meds.medication) LIKE 'dalteparin%' OR
        LOWER(meds.medication) LIKE 'fondaparinux%' OR
        LOWER(meds.medication) LIKE 'rivaroxaban%' OR
        LOWER(meds.medication) LIKE 'apixaban%' OR
        LOWER(meds.medication) LIKE 'dabigatran%' OR
        LOWER(meds.medication) LIKE 'argatroban%' OR
        LOWER(meds.medication) LIKE 'bivalirudin%' OR
        -- Antiplatelets
        LOWER(meds.medication) LIKE 'aspirin%' OR
        LOWER(meds.medication) LIKE 'clopidogrel%' OR
        LOWER(meds.medication) LIKE 'prasugrel%' OR
        LOWER(meds.medication) LIKE 'ticagrelor%' OR
        -- NSAIDs
        LOWER(meds.medication) LIKE 'ibuprofen%' OR
        LOWER(meds.medication) LIKE 'naproxen%' OR
        LOWER(meds.medication) LIKE 'ketorolac%' OR
        LOWER(meds.medication) LIKE 'diclofenac%'
      THEN 1 ELSE 0 END) AS on_bleeding_risk_drug
  FROM
    meds_first_24h AS meds
  GROUP BY
    meds.hadm_id
),

-- 4. Combine cohort outcomes with medication summaries
full_cohort_summary AS (
  SELECT
    c.hadm_id,
    c.hospital_expire_flag,
    DATETIME_DIFF(c.dischtime, c.admittime, DAY) AS los,
    COALESCE(pms.medication_complexity_score, 0) AS medication_complexity_score,
    CASE
      WHEN pms.on_qt_prolonging_drug = 1 AND pms.on_bleeding_risk_drug = 1
      THEN 'On Both QT and Bleeding Risk Drugs'
      ELSE 'Other Patients'
    END AS patient_group
  FROM
    cohort AS c
  LEFT JOIN
    patient_med_summary AS pms
    ON c.hadm_id = pms.hadm_id
),

-- 5. Calculate the MCS for the 75th percentile to define the top quartile
top_quartile_cutoff AS (
  SELECT
    APPROX_QUANTILES(medication_complexity_score, 100)[OFFSET(75)] AS mcs_p75
  FROM
    full_cohort_summary
)

-- Final Analysis: Combine results into a single output table
-- Analysis 1: MCS distribution by patient group
SELECT
  'MCS Distribution' AS analysis,
  fcs.patient_group,
  'Patient Count' AS metric,
  CAST(COUNT(fcs.hadm_id) AS STRING) AS value
FROM full_cohort_summary AS fcs
GROUP BY fcs.patient_group

UNION ALL

SELECT
  'MCS Distribution' AS analysis,
  fcs.patient_group,
  'Avg MCS' AS metric,
  CAST(ROUND(AVG(fcs.medication_complexity_score), 2) AS STRING) AS value
FROM full_cohort_summary AS fcs
GROUP BY fcs.patient_group

UNION ALL

SELECT
  'MCS Distribution' AS analysis,
  fcs.patient_group,
  'MCS 25th Percentile' AS metric,
  CAST(APPROX_QUANTILES(fcs.medication_complexity_score, 100)[OFFSET(25)] AS STRING) AS value
FROM full_cohort_summary AS fcs
GROUP BY fcs.patient_group

UNION ALL

SELECT
  'MCS Distribution' AS analysis,
  fcs.patient_group,
  'MCS 50th Percentile (Median)' AS metric,
  CAST(APPROX_QUANTILES(fcs.medication_complexity_score, 100)[OFFSET(50)] AS STRING) AS value
FROM full_cohort_summary AS fcs
GROUP BY fcs.patient_group

UNION ALL

SELECT
  'MCS Distribution' AS analysis,
  fcs.patient_group,
  'MCS 75th Percentile' AS metric,
  CAST(APPROX_QUANTILES(fcs.medication_complexity_score, 100)[OFFSET(75)] AS STRING) AS value
FROM full_cohort_summary AS fcs
GROUP BY fcs.patient_group

UNION ALL

-- Analysis 2: Outcomes for top quartile MCS patients
SELECT
  'Top Quartile Outcomes (MCS >= P75)' AS analysis,
  'All Patients in Top Quartile' AS patient_group,
  'Avg Hospital LOS (days)' AS metric,
  CAST(ROUND(AVG(fcs.los), 2) AS STRING) AS value
FROM
  full_cohort_summary AS fcs,
  top_quartile_cutoff
WHERE
  fcs.medication_complexity_score >= top_quartile_cutoff.mcs_p75

UNION ALL

SELECT
  'Top Quartile Outcomes (MCS >= P75)' AS analysis,
  'All Patients in Top Quartile' AS patient_group,
  'In-Hospital Mortality Rate (%)' AS metric,
  CAST(ROUND(AVG(fcs.hospital_expire_flag) * 100, 2) AS STRING) AS value
FROM
  full_cohort_summary AS fcs,
  top_quartile_cutoff
WHERE
  fcs.medication_complexity_score >= top_quartile_cutoff.mcs_p75
ORDER BY
  analysis,
  patient_group,
  metric;