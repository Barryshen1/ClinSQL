WITH Cohort AS (
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime
    FROM
        `physionet-data.mimiciv_3_1_hosp`.admissions ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp`.patients p
        ON ad.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 65 AND 75
        AND DATETIME_DIFF(ad.dischtime, ad.admittime, HOUR) >= 96 -- Stay duration >= 96 hours
        AND EXISTS ( -- Check for Diabetes Diagnosis (ICD-10)
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd dicd
            WHERE
                dicd.subject_id = ad.subject_id
                AND dicd.hadm_id = ad.hadm_id
                AND dicd.icd_version = 10
                AND (dicd.icd_code LIKE 'E10%' OR dicd.icd_code LIKE 'E11%' OR dicd.icd_code LIKE 'E13%' OR dicd.icd_code LIKE 'E08%' OR dicd.icd_code LIKE 'E09%')
        )
        AND EXISTS ( -- Check for Heart Failure Diagnosis (ICD-10)
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd dicd
            WHERE
                dicd.subject_id = ad.subject_id
                AND dicd.hadm_id = ad.hadm_id
                AND dicd.icd_version = 10
                AND dicd.icd_code LIKE 'I50%'
        )
)
-- Annotate EMARDrugs with insulin types and time windows for the cohort
, EMAR_Annotated_Raw AS (
    SELECT
        fc.subject_id,
        fc.hadm_id,
        em.charttime,
        LOWER(em.medication) AS medication_lower,
        -- Flag for Basal insulin drugs
        (LOWER(em.medication) LIKE '%glargine%' OR
         LOWER(em.medication) LIKE '%detemir%' OR
         LOWER(em.medication) LIKE '%degludec%' OR
         LOWER(em.medication) LIKE '%nph%') AS is_basal_drug,
        -- Flag for Bolus insulin drugs
        (LOWER(em.medication) LIKE '%lispro%' OR
         LOWER(em.medication) LIKE '%aspart%' OR
         LOWER(em.medication) LIKE '%glulisine%' OR
         LOWER(em.medication) LIKE '%regular insulin%' OR
         LOWER(em.medication) LIKE '%insulin regular%') AS is_bolus_drug,
        -- Flag for Sliding scale indicator
        (LOWER(em.medication) LIKE '%sliding scale%' OR
         -- 'SSI' often stands for Sliding Scale Insulin in this context.
         (LOWER(em.medication) LIKE '%ssi%' AND LOWER(em.medication) NOT LIKE '%ssi other%')) AS is_ssi_indicator, -- Exclude non-insulin SSI terms
        -- Time window flags
        (em.charttime BETWEEN fc.admittime AND DATETIME_ADD(fc.admittime, INTERVAL 48 HOUR)) AS in_first_48h,
        (em.charttime BETWEEN DATETIME_SUB(fc.dischtime, INTERVAL 48 HOUR) AND fc.dischtime) AS in_last_48h
    FROM
        Cohort fc
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp`.emar em
        ON fc.subject_id = em.subject_id AND fc.hadm_id = em.hadm_id
    WHERE
        LOWER(em.medication) LIKE '%insulin%' -- Primary filter for efficiency and relevance
        OR (LOWER(em.medication) LIKE '%ssi%' AND LOWER(em.medication) NOT LIKE '%ssi other%') -- Include SSI if insulin not explicitly in name
)
-- Aggregate insulin types per patient and time window
, RegimenFlags AS (
    SELECT
        subject_id,
        hadm_id,
        -- Flags for first 48 hours
        MAX(CASE WHEN in_first_48h THEN is_basal_drug ELSE FALSE END) AS has_basal_f48,
        MAX(CASE WHEN in_first_48h THEN is_bolus_drug ELSE FALSE END) AS has_bolus_f48,
        MAX(CASE WHEN in_first_48h THEN is_ssi_indicator ELSE FALSE END) AS has_ssi_f48,
        -- Flags for final 48 hours
        MAX(CASE WHEN in_last_48h THEN is_basal_drug ELSE FALSE END) AS has_basal_l48,
        MAX(CASE WHEN in_last_48h THEN is_bolus_drug ELSE FALSE END) AS has_bolus_l48,
        MAX(CASE WHEN in_last_48h THEN is_ssi_indicator ELSE FALSE END) AS has_ssi_l48
    FROM
        EMAR_Annotated_Raw
    GROUP BY
        subject_id, hadm_id
)
-- Determine the primary insulin regimen for each patient in each time window (mutually exclusive)
, DerivedRegimens AS (
    SELECT
        subject_id,
        hadm_id,
        -- Regimen for first 48 hours
        CASE
            WHEN has_basal_f48 AND has_bolus_f48 THEN 'Basal-Bolus'
            WHEN has_basal_f48 AND NOT has_bolus_f48 THEN 'Basal Only'
            -- 'Sliding Scale Only' if no specific basal/bolus drugs were identified, but an explicit SSI indicator was present
            WHEN NOT has_basal_f48 AND NOT has_bolus_f48 AND has_ssi_f48 THEN 'Sliding Scale Only'
            WHEN NOT has_basal_f48 AND has_bolus_f48 THEN 'Bolus Only'
            ELSE 'No Insulin'
        END AS regimen_f48,
        -- Regimen for final 48 hours
        CASE
            WHEN has_basal_l48 AND has_bolus_l48 THEN 'Basal-Bolus'
            WHEN has_basal_l48 AND NOT has_bolus_l48 THEN 'Basal Only'
            WHEN NOT has_basal_l48 AND NOT has_bolus_l48 AND has_ssi_l48 THEN 'Sliding Scale Only'
            WHEN NOT has_basal_l48 AND has_bolus_l48 THEN 'Bolus Only'
            ELSE 'No Insulin'
        END AS regimen_l48
    FROM
        RegimenFlags
)
-- Total number of unique patient admissions in the cohort
, TotalCohortPatients AS (
    SELECT COUNT(DISTINCT hadm_id) AS total_patients
    FROM Cohort
)
-- Calculate percentages for first 48h
SELECT
    'First 48h' AS time_window,
    regimen_f48 AS insulin_regimen,
    COUNT(DISTINCT hadm_id) AS num_patients,
    ROUND(COUNT(DISTINCT hadm_id) * 100.0 / (SELECT total_patients FROM TotalCohortPatients), 2) AS percentage
FROM
    DerivedRegimens
GROUP BY
    regimen_f48

UNION ALL

-- Calculate percentages for final 48h
SELECT
    'Final 48h' AS time_window,
    regimen_l48 AS insulin_regimen,
    COUNT(DISTINCT hadm_id) AS num_patients,
    ROUND(COUNT(DISTINCT hadm_id) * 100.0 / (SELECT total_patients FROM TotalCohortPatients), 2) AS percentage
FROM
    DerivedRegimens
GROUP BY
    regimen_l48

UNION ALL

-- Calculate transitions between first 48h and final 48h regimens
SELECT
    'Transitions' AS time_window,
    CONCAT(regimen_f48, ' -> ', regimen_l48) AS insulin_regimen,
    COUNT(DISTINCT hadm_id) AS num_patients,
    ROUND(COUNT(DISTINCT hadm_id) * 100.0 / (SELECT total_patients FROM TotalCohortPatients), 2) AS percentage
FROM
    DerivedRegimens
GROUP BY
    regimen_f48, regimen_l48
ORDER BY
    time_window, num_patients DESC;