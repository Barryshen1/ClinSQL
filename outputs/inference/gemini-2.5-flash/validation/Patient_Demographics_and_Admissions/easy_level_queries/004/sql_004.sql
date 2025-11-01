WITH akicodes AS (
    SELECT
        icd_code,
        icd_version
    FROM
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE
        (icd_version = 9 AND icd_code LIKE '584.%') -- ICD-9 codes for Acute kidney failure
        OR (icd_version = 10 AND icd_code LIKE 'N17.%') -- ICD-10 codes for Acute kidney failure
),
-- Step 2: Retrieve admissions data, patient demographics, calculate age at admission and LOS,
-- and rank admissions to identify the first one for each patient.
admissions_data AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        p.gender,
        p.anchor_age,
        p.anchor_year,
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
        -- Calculate age at admission: anchor_age + years passed since anchor_year
        p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_at_admission,
        -- Rank each admission for a subject to find their first admission
        ROW_NUMBER() OVER (PARTITION BY adm.subject_id ORDER BY adm.admittime) as rn
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON adm.subject_id = p.subject_id
),
-- Step 3: Filter for the specific cohort: first admission, female, age 70-80, and valid LOS.
cohort_admissions AS (
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.los_days,
        ad.age_at_admission
    FROM
        admissions_data ad
    WHERE
        ad.rn = 1 -- Only consider the patient's first admission
        AND ad.gender = 'F' -- Filter for female patients
        -- Ensure age is between 70 and 80 at the time of admission.
        -- We also explicitly exclude patients originally marked as 90+ (due to MIMIC-IV age handling)
        -- to ensure their true age falls within 70-80 range.
        AND ad.age_at_admission >= 70
        AND ad.age_at_admission <= 80
        AND ad.anchor_age < 90 -- Exclude patients whose recorded anchor_age was 90 or higher
        AND ad.los_days IS NOT NULL -- Exclude admissions with missing discharge or admission times
        AND ad.los_days >= 0 -- Exclude admissions with illogical negative length of stay
)
-- Step 4: Join the filtered cohort with diagnoses to identify AKI patients
-- and then calculate the standard deviation of their length of stay.
SELECT
    STDDEV(ca.los_days) AS stddev_los_days_for_aki_females_70_80
FROM
    cohort_admissions ca
JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON ca.subject_id = di.subject_id AND ca.hadm_id = di.hadm_id
JOIN
    akicodes ak
    ON di.icd_code = ak.icd_code AND di.icd_version = ak.icd_version;