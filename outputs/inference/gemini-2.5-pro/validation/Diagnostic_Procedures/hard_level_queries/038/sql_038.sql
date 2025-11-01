WITH first_stays AS (
    SELECT
        subject_id,
        hadm_id,
        stay_id,
        intime,
        los,
        -- Rank stays within a hospital admission by their start time
        ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY intime) AS rn
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays`
),

-- Step 2: Define the specific cohort of interest: male patients, aged 60-70,
-- with intracranial hemorrhage, on their first ICU stay.
ich_cohort AS (
    SELECT DISTINCT -- Use DISTINCT to avoid duplicates from multiple ICH codes per admission
        fs.subject_id,
        fs.hadm_id,
        fs.stay_id,
        fs.intime,
        fs.los
    FROM
        first_stays AS fs
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON fs.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        ON fs.hadm_id = dx.hadm_id
    WHERE
        fs.rn = 1 -- Only the first ICU stay of the admission
        AND pat.gender = 'M'
        AND pat.anchor_age BETWEEN 60 AND 70
        AND (
            -- Intracranial Hemorrhage ICD-9 and ICD-10 codes
            STARTS_WITH(dx.icd_code, '430') OR
            STARTS_WITH(dx.icd_code, '431') OR
            STARTS_WITH(dx.icd_code, '432') OR
            STARTS_WITH(dx.icd_code, 'I60') OR
            STARTS_WITH(dx.icd_code, 'I61') OR
            STARTS_WITH(dx.icd_code, 'I62')
        )
),

-- Step 3: Count procedures from `procedureevents` for the ICH cohort in the first 72 hours.
procedure_counts AS (
    SELECT
        ic.stay_id,
        COUNT(pe.itemid) AS procedure_count
    FROM
        ich_cohort AS ic
    INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
        ON ic.stay_id = pe.stay_id
    WHERE
        -- Procedures must start within the first 72 hours of the ICU stay
        pe.starttime >= ic.intime AND pe.starttime <= TIMESTAMP_ADD(ic.intime, INTERVAL 72 HOUR)
    GROUP BY
        ic.stay_id
),

-- Step 4: Calculate the 75th percentile procedure burden and other metrics for the ICH cohort.
ich_metrics AS (
    SELECT
        -- Calculate the 75th percentile of procedure counts
        APPROX_QUANTILES(COALESCE(pc.procedure_count, 0), 100)[OFFSET(75)] AS percentile_75_procedure_burden_ich,
        -- Calculate mean ICU LOS and hospital mortality
        AVG(ic.los) AS mean_icu_los_days_ich,
        AVG(adm.hospital_expire_flag) AS hospital_mortality_ich
    FROM
        ich_cohort AS ic
    -- LEFT JOIN to include patients from the cohort who had 0 procedures in the timeframe
    LEFT JOIN procedure_counts AS pc
        ON ic.stay_id = pc.stay_id
    -- Join with admissions to get mortality flag
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON ic.hadm_id = adm.hadm_id
),

-- Step 5: Calculate metrics for the general ICU population (all first stays).
general_pop_metrics AS (
    SELECT
        AVG(fs.los) AS mean_icu_los_days_general,
        AVG(adm.hospital_expire_flag) AS hospital_mortality_general
    FROM
        first_stays AS fs
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON fs.hadm_id = adm.hadm_id
    WHERE fs.rn = 1
)

-- Step 6: Combine results from the ICH cohort and general population into a single row.
SELECT
    ich.percentile_75_procedure_burden_ich,
    ich.mean_icu_los_days_ich,
    ich.hospital_mortality_ich,
    gen.mean_icu_los_days_general,
    gen.hospital_mortality_general
FROM
    ich_metrics AS ich,
    general_pop_metrics AS gen;