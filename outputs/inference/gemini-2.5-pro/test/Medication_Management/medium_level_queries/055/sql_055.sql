WITH
-- Step 1: Identify hospital admissions with both T2DM and Heart Failure diagnoses
diagnoses AS (
    SELECT
        hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        -- ICD-10 codes
        (icd_version = 10 AND (
            icd_code LIKE 'E11%' -- Type 2 diabetes mellitus
            OR icd_code LIKE 'I50%' -- Heart failure
        ))
        -- ICD-9 codes
        OR (icd_version = 9 AND (
            icd_code LIKE '250%' -- Diabetes mellitus (includes Type 2)
            OR icd_code LIKE '428%' -- Heart failure
        ))
    GROUP BY
        hadm_id
    HAVING
        -- Ensure both conditions are present for the admission
        COUNT(DISTINCT
            CASE
                WHEN icd_code LIKE 'E11%' OR icd_code LIKE '250%' THEN 'T2DM'
                WHEN icd_code LIKE 'I50%' OR icd_code LIKE '428%' THEN 'HF'
            END
        ) = 2
),

-- Step 2: Define the patient cohort: 39-49y females with T2DM & HF, ICU LOS >= 72h
cohort AS (
    SELECT
        icu.subject_id,
        icu.hadm_id,
        icu.stay_id,
        icu.intime,
        icu.outtime
    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON icu.hadm_id = adm.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON icu.subject_id = pat.subject_id
    -- Ensure the admission has the required diagnoses
    INNER JOIN diagnoses AS dx
        ON icu.hadm_id = dx.hadm_id
    WHERE
        pat.gender = 'F'
        -- Calculate age at admission and filter
        AND (pat.anchor_age + EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) BETWEEN 39 AND 49
        -- Filter for ICU length of stay >= 72 hours
        AND DATETIME_DIFF(icu.outtime, icu.intime, HOUR) >= 72
),

-- Step 3: Identify and categorize all relevant insulin administrations
insulin_events AS (
    -- Basal and Bolus insulins by itemid
    SELECT
        stay_id,
        starttime,
        CASE
            WHEN itemid IN (223258, 223259, 223262) THEN 'Basal' -- Glargine, Detemir, NPH
            WHEN itemid IN (223254, 223260, 229619) THEN 'Bolus' -- Regular, Aspart, Lispro
        END AS insulin_type
    FROM `physionet-data.mimiciv_3_1_icu.inputevents`
    WHERE itemid IN (
        223258, 223259, 223262, -- Basal
        223254, 223260, 229619  -- Bolus
    ) AND stay_id IN (SELECT stay_id FROM cohort)

    UNION ALL

    -- Sliding scale insulin by order category
    SELECT
        stay_id,
        starttime,
        'Sliding-Scale' AS insulin_type
    FROM `physionet-data.mimiciv_3_1_icu.inputevents`
    WHERE ordercategorydescription = 'Sliding Scale Insulin'
      AND stay_id IN (SELECT stay_id FROM cohort)
),

-- Step 4: Determine the first administration time for each insulin type per stay
first_administrations AS (
    SELECT
        stay_id,
        insulin_type,
        MIN(starttime) AS initiation_time
    FROM insulin_events
    GROUP BY stay_id, insulin_type
),

-- Step 5: Flag stays based on when Basal, Bolus, or SSI were initiated
stay_level_flags AS (
    SELECT
        c.stay_id,
        -- Basal initiation flags
        MAX(CASE WHEN fa.insulin_type = 'Basal' AND fa.initiation_time BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END) AS init_basal_72h,
        MAX(CASE WHEN fa.insulin_type = 'Basal' AND fa.initiation_time BETWEEN DATETIME_SUB(c.outtime, INTERVAL 48 HOUR) AND c.outtime THEN 1 ELSE 0 END) AS init_basal_48h,
        -- Bolus initiation flags
        MAX(CASE WHEN fa.insulin_type = 'Bolus' AND fa.initiation_time BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END) AS init_bolus_72h,
        MAX(CASE WHEN fa.insulin_type = 'Bolus' AND fa.initiation_time BETWEEN DATETIME_SUB(c.outtime, INTERVAL 48 HOUR) AND c.outtime THEN 1 ELSE 0 END) AS init_bolus_48h,
        -- Sliding Scale initiation flags
        MAX(CASE WHEN fa.insulin_type = 'Sliding-Scale' AND fa.initiation_time BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END) AS init_ssi_72h,
        MAX(CASE WHEN fa.insulin_type = 'Sliding-Scale' AND fa.initiation_time BETWEEN DATETIME_SUB(c.outtime, INTERVAL 48 HOUR) AND c.outtime THEN 1 ELSE 0 END) AS init_ssi_48h
    FROM cohort AS c
    LEFT JOIN first_administrations AS fa
        ON c.stay_id = fa.stay_id
    GROUP BY c.stay_id, c.intime, c.outtime
),

-- Step 6: Create flags for Basal-Bolus initiation
basal_bolus_flags AS (
    SELECT
        *,
        -- A patient initiated Basal-Bolus if BOTH were initiated in the window. Cast BOOL to INT64 for AVG().
        CAST((init_basal_72h = 1 AND init_bolus_72h = 1) AS INT64) AS init_basal_bolus_72h,
        CAST((init_basal_48h = 1 AND init_bolus_48h = 1) AS INT64) AS init_basal_bolus_48h
    FROM stay_level_flags
),

-- Step 7: Aggregate flags to calculate percentages for the entire cohort
final_summary AS (
    SELECT
        AVG(init_basal_72h) AS pct_basal_72h,
        AVG(init_basal_48h) AS pct_basal_48h,
        AVG(init_bolus_72h) AS pct_bolus_72h,
        AVG(init_bolus_48h) AS pct_bolus_48h,
        AVG(init_basal_bolus_72h) AS pct_basal_bolus_72h,
        AVG(init_basal_bolus_48h) AS pct_basal_bolus_48h,
        AVG(init_ssi_72h) AS pct_ssi_72h,
        AVG(init_ssi_48h) AS pct_ssi_48h
    FROM basal_bolus_flags
)

-- Step 8: Unpivot the summary data into the final report format
SELECT
    'Basal' AS insulin_regimen,
    ROUND(pct_basal_72h * 100, 2) AS percent_initiated_first_72h,
    ROUND(pct_basal_48h * 100, 2) AS percent_initiated_final_48h,
    ROUND((pct_basal_72h - pct_basal_48h) * 100, 2) AS absolute_difference_pp
FROM final_summary

UNION ALL

SELECT
    'Bolus' AS insulin_regimen,
    ROUND(pct_bolus_72h * 100, 2) AS percent_initiated_first_72h,
    ROUND(pct_bolus_48h * 100, 2) AS percent_initiated_final_48h,
    ROUND((pct_bolus_72h - pct_bolus_48h) * 100, 2) AS absolute_difference_pp
FROM final_summary

UNION ALL

SELECT
    'Basal-Bolus' AS insulin_regimen,
    ROUND(pct_basal_bolus_72h * 100, 2) AS percent_initiated_first_72h,
    ROUND(pct_basal_bolus_48h * 100, 2) AS percent_initiated_final_48h,
    ROUND((pct_basal_bolus_72h - pct_basal_bolus_48h) * 100, 2) AS absolute_difference_pp
FROM final_summary

UNION ALL

SELECT
    'Sliding-Scale' AS insulin_regimen,
    ROUND(pct_ssi_72h * 100, 2) AS percent_initiated_first_72h,
    ROUND(pct_ssi_48h * 100, 2) AS percent_initiated_final_48h,
    ROUND((pct_ssi_72h - pct_ssi_48h) * 100, 2) AS absolute_difference_pp
FROM final_summary
ORDER BY insulin_regimen;