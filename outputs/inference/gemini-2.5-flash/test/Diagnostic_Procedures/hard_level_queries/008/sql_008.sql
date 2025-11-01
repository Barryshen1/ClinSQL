WITH base_cohort AS (
    SELECT
        p.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag,
        icu.stay_id,
        icu.intime AS icu_intime
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON p.subject_id = adm.subject_id
    JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` AS icu
        ON adm.hadm_id = icu.hadm_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 48 AND 58 -- Age at admission based on anchor_age
),
-- Step 2: Filter for admissions with Upper GI Bleeding (UGIB) diagnosis
ugib_admissions AS (
    SELECT
        DISTINCT bc.subject_id,
        bc.hadm_id,
        bc.admittime,
        bc.dischtime,
        bc.hospital_expire_flag,
        bc.icu_intime
    FROM
        base_cohort AS bc
    JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
        ON bc.hadm_id = diag.hadm_id
    WHERE
        -- ICD-9 codes for Upper GI Bleeding
        (diag.icd_version = 9 AND diag.icd_code IN (
            '53082', -- Esophageal hemorrhage
            '53100', '53101', '53120', '53121', '53140', '53141', '53160', '53161', -- Gastric ulcer w/ hemorrhage
            '53200', '53201', '53220', '53221', '53240', '53241', '53260', '53261', -- Duodenal ulcer w/ hemorrhage
            '53300', '53301', '53320', '53321', '53340', '53341', '53360', '53361', -- Peptic ulcer NOS w/ hemorrhage
            '53501', '53511', '53521', '53531', '53541', '53551', -- Gastritis, duodenitis w/ hemorrhage
            '5780',  -- Hematemesis
            '5781'   -- Melena
            -- K92.2 / 578.9 (Unspecified GI hemorrhage) are intentionally omitted for specificity to 'upper' GI
        ))
        OR
        -- ICD-10 codes for Upper GI Bleeding
        (diag.icd_version = 10 AND diag.icd_code IN (
            'K2081', -- Esophagitis with bleeding
            'K226',  -- Gastro-esophageal laceration-hemorrhage syndrome
            'K250', 'K252', 'K254', 'K256', -- Gastric ulcer with hemorrhage
            'K260', 'K262', 'K264', 'K266', -- Duodenal ulcer with hemorrhage
            'K270', 'K272', 'K274', 'K276', -- Peptic ulcer, site unspecified, with hemorrhage
            'K2901', 'K2921', 'K2931', 'K2941', 'K2951', 'K2961', 'K2971', 'K2981', 'K2991', -- Gastritis and duodenitis with hemorrhage
            'K920',  -- Hematemesis
            'K921'   -- Melena
            -- K92.2 (Unspecified GI hemorrhage) is intentionally omitted for specificity to 'upper' GI
        ))
),
-- Step 3: Count diagnostic procedures performed in the first 24 hours of ICU stay
procedures_24hr AS (
    SELECT
        uga.subject_id,
        uga.hadm_id,
        COUNT(proc.icd_code) AS procedure_count_24hr -- Total procedure instances
    FROM
        ugib_admissions AS uga
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
        ON uga.hadm_id = proc.hadm_id
        AND proc.chartdate >= uga.icu_intime
        AND proc.chartdate < DATETIME_ADD(uga.icu_intime, INTERVAL 24 HOUR)
    GROUP BY
        uga.subject_id, uga.hadm_id
),
-- Step 4: Combine all relevant patient data and calculate hospital LOS
patient_data AS (
    SELECT
        uga.subject_id,
        uga.hadm_id,
        COALESCE(p24.procedure_count_24hr, 0) AS procedure_count_24hr, -- Handle admissions with 0 procedures
        DATETIME_DIFF(uga.dischtime, uga.admittime, HOUR) / 24.0 AS hospital_los_days,
        uga.hospital_expire_flag
    FROM
        ugib_admissions AS uga
    LEFT JOIN
        procedures_24hr AS p24
        ON uga.subject_id = p24.subject_id AND uga.hadm_id = p24.hadm_id
),
-- Step 5: Assign quintiles based on the 24-hour procedure count
quintile_assignment AS (
    SELECT
        subject_id,
        hadm_id,
        procedure_count_24hr,
        hospital_los_days,
        hospital_expire_flag,
        NTILE(5) OVER (ORDER BY procedure_count_24hr) AS procedure_quintile
    FROM
        patient_data
)
-- Step 6: Aggregate results by quintile
SELECT
    procedure_quintile,
    COUNT(DISTINCT hadm_id) AS patient_count,
    AVG(procedure_count_24hr) AS avg_procedures_24hr,
    AVG(hospital_los_days) AS avg_hospital_los_days,
    SUM(hospital_expire_flag) * 100.0 / COUNT(hospital_expire_flag) AS in_hospital_mortality_percent
FROM
    quintile_assignment
GROUP BY
    procedure_quintile
ORDER BY
    procedure_quintile;