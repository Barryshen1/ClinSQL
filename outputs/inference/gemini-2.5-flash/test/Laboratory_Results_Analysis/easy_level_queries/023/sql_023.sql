WITH sepsis_admissions AS (
    -- Step 1: Identify admissions related to sepsis diagnoses
    SELECT DISTINCT hadm_id, subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        -- ICD-9 codes for sepsis and septic shock
        (icd_version = 9 AND icd_code IN ('99591', '99592', '78552'))
        -- ICD-10 codes for sepsis
        OR (icd_version = 10 AND (icd_code LIKE 'A40%' OR icd_code LIKE 'A41%'))
),
male_sepsis_discharge_info AS (
    -- Step 2 & 3: Filter for male patients and get their discharge dates for sepsis admissions
    SELECT
        sa.subject_id,
        sa.hadm_id,
        DATE(adm.dischtime) AS discharge_date -- Extract only the date part for comparison
    FROM sepsis_admissions sa
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON sa.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON sa.hadm_id = adm.hadm_id
    WHERE p.gender = 'M'
),
lactate_on_discharge AS (
    -- Step 4 & 5: Retrieve serum lactate values specifically on the discharge day
    SELECT
        le.valuenum AS lactate_value
    FROM male_sepsis_discharge_info msdi
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON msdi.subject_id = le.subject_id
        AND msdi.hadm_id = le.hadm_id
    WHERE
        le.itemid = 50813 -- Common itemid for Lactate (checked in d_labitems)
        AND le.valuenum IS NOT NULL -- Ensure a numerical value exists
        AND DATE(le.charttime) = msdi.discharge_date -- Lab event occurred on the discharge date
)
-- Step 6: Calculate the Interquartile Range (IQR)
SELECT
    PERCENTILE_CONT(lactate_value, 0.75) OVER() -
    PERCENTILE_CONT(lactate_value, 0.25) OVER() AS iqr_of_serum_lactate
FROM lactate_on_discharge
QUALIFY ROW_NUMBER() OVER() = 1;