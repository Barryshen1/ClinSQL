WITH admissions_cohort AS (
    SELECT
        pa.subject_id,
        ad.hadm_id,
        pa.gender,
        pa.anchor_age,
        ad.admittime,
        ad.dischtime,
        DATETIME_DIFF(ad.dischtime, ad.admittime, DAY) AS los_days,
        CASE
            WHEN DATETIME_DIFF(ad.dischtime, ad.admittime, DAY) <= 7 THEN 'LOS_LE_7_DAYS'
            ELSE 'LOS_GT_7_DAYS'
        END AS los_group,
        ad.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pa
        ON ad.subject_id = pa.subject_id
    WHERE
        pa.gender = 'F'
        AND pa.anchor_age BETWEEN 79 AND 89
),
-- Step 2: Identify admissions with Community-Acquired or Aspiration Pneumonia
-- Common ICD-9 and ICD-10 codes for CAP and Aspiration Pneumonia
pneumonia_hadm AS (
    SELECT DISTINCT hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        -- ICD-9 codes (prior to Oct 2015) for Community-Acquired/Unspecified Pneumonia and Aspiration Pneumonia
        (icd_version = 9 AND icd_code IN (
            '4800', '4801', '4802', '4803', '4808', '4809', -- Viral Pneumonia
            '481', -- Pneumococcal pneumonia
            '4820', '4821', '4822', '4823', '4824', '4828', '4829', -- Other bacterial pneumonia
            '4830', '4831', '4838', -- Pneumonia due to other specified organism
            '485', -- Bronchopneumonia, organism unspecified
            '486', -- Pneumonia, organism unspecified (very common for CAP)
            '5070' -- Pneumonitis due to inhalation of food or vomitus (Aspiration pneumonia)
        ))
        OR
        -- ICD-10 codes (Oct 2015 onwards) for Community-Acquired/Unspecified Pneumonia and Aspiration Pneumonia
        (icd_version = 10 AND icd_code IN (
            'J13', -- Pneumonia due to Streptococcus pneumoniae
            'J14', -- Pneumonia due to Haemophilus influenzae
            'J150', 'J151', 'J152', 'J153', 'J154', 'J155', 'J156', 'J157', 'J158', 'J159', -- Other bacterial pneumonia
            'J160', 'J168', -- Pneumonia due to other infectious organisms
            'J180', 'J181', 'J182', 'J188', 'J189', -- Pneumonia, unspecified organism (very common for CAP)
            'J690' -- Pneumonitis due to food and vomit (Aspiration pneumonia)
        ))
),
-- Step 3: Combine base cohort with pneumonia diagnoses to get the final study population
filtered_cohort AS (
    SELECT
        ac.*
    FROM
        admissions_cohort ac
    JOIN
        pneumonia_hadm pn
        ON ac.hadm_id = pn.hadm_id
),
-- Step 4.1: Identify admissions with mechanical ventilation within 24 hours of ICU admission
mech_vent_hadm AS (
    SELECT DISTINCT icu.hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON icu.stay_id = ce.stay_id
        AND ce.charttime BETWEEN icu.intime AND DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
        AND ce.itemid IN (
            224639, -- Ventilator Mode
            224686, -- Tidal Volume (Set)
            224687, -- Minute Volume (Set)
            224690, -- Respiratory Mode
            227287, -- Ventilator Status (check if active)
            224700, -- PEEP
            220005, -- Ventilator Settings
            224417  -- Ventilation Rate (Set)
        )
        AND ce.valuenum IS NOT NULL -- ensure there's an actual numeric value charted
    WHERE icu.hadm_id IN (SELECT hadm_id FROM filtered_cohort) -- Pre-filter for efficiency
),
-- Step 4.2: Identify admissions with vasopressors within 24 hours of ICU admission
vasopressor_hadm AS (
    SELECT DISTINCT icu.hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie
        ON icu.stay_id = ie.stay_id
        AND ie.starttime BETWEEN icu.intime AND DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
        AND ie.itemid IN (
            221906, -- Norepinephrine
            221289, -- Epinephrine
            222340, -- Vasopressin
            223003, -- Dopamine
            221749  -- Phenylephrine
        )
        AND ie.amount > 0 -- ensure an actual non-zero amount was administered
    WHERE icu.hadm_id IN (SELECT hadm_id FROM filtered_cohort)
),
-- Step 4.3: Identify admissions with RRT within 24 hours of ICU admission
rrt_hadm AS (
    SELECT DISTINCT icu.hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
        ON icu.stay_id = pe.stay_id
        AND pe.starttime BETWEEN icu.intime AND DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
        AND pe.itemid IN (
            225792, -- CRRT
            225805, -- Dialysis Machine
            225806, -- Dialysis Type
            225816, -- Hemodialysis
            225817, -- Peritoneal Dialysis
            225818  -- Ultrafiltration
        )
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON icu.stay_id = ce.stay_id
        AND ce.charttime BETWEEN icu.intime AND DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
        AND ce.itemid IN (
            225792, -- CRRT
            225793, -- CRRT - Current Goal Fluid Removal
            225795, -- CRRT - Pre Medication
            225805, -- Dialysis Machine
            225806, -- Dialysis Type
            225816, -- Hemodialysis
            225817, -- Peritoneal Dialysis
            225818, -- Ultrafiltration
            225323  -- Dialysis Status
        )
        AND ce.valuenum IS NOT NULL -- ensure a value was charted
    WHERE (pe.itemid IS NOT NULL OR ce.itemid IS NOT NULL) -- Ensure at least one RRT event happened
    AND icu.hadm_id IN (SELECT hadm_id FROM filtered_cohort)
),
-- Step 4.4: Identify all admissions with an ICU stay in the cohort
icu_admissions AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
    WHERE hadm_id IN (SELECT hadm_id FROM filtered_cohort)
),
-- Step 5: Consolidate intervention flags for each hadm_id
icu_interventions_results AS (
    SELECT
        fc.hadm_id,
        CASE WHEN ia.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS had_icu_stay,
        CASE WHEN mv.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS mech_vent_day1,
        CASE WHEN vp.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS vasopressor_day1,
        CASE WHEN rr.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS rrt_day1
    FROM filtered_cohort fc
    LEFT JOIN icu_admissions ia ON fc.hadm_id = ia.hadm_id
    LEFT JOIN mech_vent_hadm mv ON fc.hadm_id = mv.hadm_id
    LEFT JOIN vasopressor_hadm vp ON fc.hadm_id = vp.hadm_id
    LEFT JOIN rrt_hadm rr ON fc.hadm_id = rr.hadm_id
),
-- Step 6: Combine filtered cohort with intervention flags.
-- COALESCE ensures patients without an ICU stay or without recorded interventions get 0 for the flags.
final_patient_level_data AS (
    SELECT
        fc.hadm_id,
        fc.los_group,
        fc.hospital_expire_flag,
        COALESCE(iir.had_icu_stay, 0) AS had_icu_stay,
        COALESCE(iir.mech_vent_day1, 0) AS mech_vent_day1,
        COALESCE(iir.vasopressor_day1, 0) AS vasopressor_day1,
        COALESCE(iir.rrt_day1, 0) AS rrt_day1
    FROM
        filtered_cohort fc
    LEFT JOIN
        icu_interventions_results iir
        ON fc.hadm_id = iir.hadm_id
)
-- Step 7: Final aggregation to calculate mortality and prevalence by LOS group
SELECT
    los_group,
    COUNT(DISTINCT hadm_id) AS total_admissions,
    SUM(hospital_expire_flag) AS in_hospital_deaths,
    ROUND(CAST(SUM(hospital_expire_flag) AS BIGNUMERIC) * 100 / COUNT(DISTINCT hadm_id), 2) AS mortality_rate_percent,
    SUM(had_icu_stay) AS day1_icu_admissions_count,
    ROUND(CAST(SUM(had_icu_stay) AS BIGNUMERIC) * 100 / COUNT(DISTINCT hadm_id), 2) AS day1_icu_prevalence_percent,
    SUM(mech_vent_day1) AS mech_vent_day1_count,
    ROUND(CAST(SUM(mech_vent_day1) AS BIGNUMERIC) * 100 / COUNT(DISTINCT hadm_id), 2) AS mech_vent_day1_prevalence_percent,
    SUM(vasopressor_day1) AS vasopressor_day1_count,
    ROUND(CAST(SUM(vasopressor_day1) AS BIGNUMERIC) * 100 / COUNT(DISTINCT hadm_id), 2) AS vasopressor_day1_prevalence_percent,
    SUM(rrt_day1) AS rrt_day1_count,
    ROUND(CAST(SUM(rrt_day1) AS BIGNUMERIC) * 100 / COUNT(DISTINCT hadm_id), 2) AS rrt_day1_prevalence_percent
FROM
    final_patient_level_data
GROUP BY
    los_group
ORDER BY
    los_group;