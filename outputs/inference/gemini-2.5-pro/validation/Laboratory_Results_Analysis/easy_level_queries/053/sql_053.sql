WITH patient_cohort AS (
    SELECT DISTINCT adm.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        ON adm.hadm_id = dx.hadm_id
    WHERE
        -- Filter for 82-year-old female patients
        pat.gender = 'F'
        AND pat.anchor_age = 82
        -- Filter for Ischemic Stroke diagnoses using both ICD-9 and ICD-10 codes
        AND (
            (dx.icd_version = 9 AND (dx.icd_code LIKE '433%' OR dx.icd_code LIKE '434%'))
            OR (dx.icd_version = 10 AND dx.icd_code LIKE 'I63%')
        )
),

-- Step 2: Find the first serum glucose measurement within 24 hours of admission for this cohort.
first_admission_glucose AS (
    SELECT
        le.hadm_id,
        le.valuenum
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON le.hadm_id = adm.hadm_id
    -- Ensure we are only looking at the admissions from our target cohort
    WHERE le.hadm_id IN (SELECT hadm_id FROM patient_cohort)
        -- itemid 50931 corresponds to 'Glucose' in blood
        AND le.itemid = 50931
        AND le.valuenum IS NOT NULL
        -- Units must be mg/dL as specified
        AND le.valueuom = 'mg/dL'
        -- The measurement must be within the first 24 hours of admission
        AND le.charttime BETWEEN adm.admittime AND DATETIME_ADD(adm.admittime, INTERVAL 24 HOUR)
    -- Use QUALIFY to filter for the first measurement for each admission, which is cleaner than a subquery.
    QUALIFY ROW_NUMBER() OVER(PARTITION BY le.hadm_id ORDER BY le.charttime ASC) = 1
)

-- Step 3: Calculate the 75th percentile of the collected admission glucose values.
SELECT
    APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS glucose_mg_dl_75th_percentile
FROM first_admission_glucose;