WITH ami_cohort AS (
    -- Step 1: Identify hospital admissions for male patients aged 49-59 with an AMI diagnosis
    SELECT DISTINCT dia.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients` pat
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dia
        ON pat.subject_id = dia.subject_id
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 49 AND 59
        AND (
            -- ICD-9 codes for AMI start with '410'
            (dia.icd_version = 9 AND SUBSTR(dia.icd_code, 1, 3) = '410')
            -- ICD-10 codes for AMI start with 'I21'
            OR (dia.icd_version = 10 AND SUBSTR(dia.icd_code, 1, 3) = 'I21')
        )
),
first_troponin AS (
    -- Step 2: Find the first Troponin T measurement for each hospital admission
    SELECT
        hadm_id,
        valuenum,
        -- Rank measurements by time to find the first one
        ROW_NUMBER() OVER(PARTITION BY hadm_id ORDER BY charttime ASC) as rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents`
    WHERE
        itemid = 51003 -- itemid for 'Troponin T'
        AND valuenum IS NOT NULL
        AND valueuom = 'ng/mL' -- Ensure correct unit as per the question
),
final_cohort_values AS (
    -- Step 3: Join the patient cohort with their first troponin value and apply the value filter
    SELECT
        ft.valuenum
    FROM ami_cohort ac
    JOIN first_troponin ft
        ON ac.hadm_id = ft.hadm_id
    WHERE
        ft.rn = 1 -- Only the first measurement
        AND ft.valuenum > 0.04 -- Filter for initial troponin > 0.04 ng/mL
)
-- Step 4: Calculate the median and IQR on the final set of values
SELECT
    -- Median is the 50th percentile
    (APPROX_QUANTILES(valuenum, 100))[OFFSET(50)] AS median_troponin_t,
    -- IQR is the 75th percentile minus the 25th percentile
    (APPROX_QUANTILES(valuenum, 100))[OFFSET(75)] - (APPROX_QUANTILES(valuenum, 100))[OFFSET(25)] AS iqr_troponin_t
FROM final_cohort_values;