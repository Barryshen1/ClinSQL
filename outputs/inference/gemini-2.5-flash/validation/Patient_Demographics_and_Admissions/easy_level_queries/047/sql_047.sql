WITH Patients_Demographics_Filtered AS (
    -- Step 1: Filter patients by gender and age
    SELECT
        p.subject_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 82 AND 92
),
Patients_With_AKI AS (
    -- Step 2: Identify subject_ids who ever had an AKI diagnosis within the filtered demographic
    SELECT DISTINCT
        pdf.subject_id
    FROM
        Patients_Demographics_Filtered pdf
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON pdf.subject_id = di.subject_id
    WHERE
        -- ICD-9 codes for AKI (584.x) or ICD-10 codes for AKI (N17.x)
        (di.icd_version = 9 AND di.icd_code LIKE '584%')
        OR
        (di.icd_version = 10 AND di.icd_code LIKE 'N17%')
),
First_ICU_Stay_For_AKI_Patients AS (
    -- Step 3: Get the chronologically first ICU stay's LOS for each patient in the AKI cohort
    SELECT
        icu.subject_id,
        icu.los,
        ROW_NUMBER() OVER (PARTITION BY icu.subject_id ORDER BY icu.intime) as rn
    FROM
        Patients_With_AKI pwa
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON pwa.subject_id = icu.subject_id
)
-- Step 4: Calculate the 25th percentile of these first ICU LOS values
SELECT
    APPROX_QUANTILES(los, 4)[OFFSET(1)] AS p25_first_icu_los_days
FROM
    First_ICU_Stay_For_AKI_Patients
WHERE
    rn = 1;