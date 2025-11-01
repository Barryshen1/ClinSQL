WITH admissions_acs_cohort AS (
    -- Step 1: Select admissions for male patients aged 43-53 with an ACS diagnosis.
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ad.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 43 AND 53
        -- Check for ACS diagnosis using common ICD codes
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            WHERE
                di.subject_id = ad.subject_id
                AND di.hadm_id = ad.hadm_id
                AND (
                    -- ICD-10 codes for Acute Coronary Syndrome
                    (di.icd_version = 10 AND (
                        di.icd_code LIKE 'I20%' OR -- Angina pectoris
                        di.icd_code LIKE 'I21%' OR -- Acute myocardial infarction
                        di.icd_code LIKE 'I22%' OR -- Subsequent myocardial infarction
                        di.icd_code LIKE 'I24%' OR -- Other acute ischemic heart diseases
                        di.icd_code LIKE 'I25%'    -- Chronic ischemic heart disease (often included in ACS definition for studies)
                    ))
                    OR
                    -- ICD-9 codes for Acute Coronary Syndrome
                    (di.icd_version = 9 AND (
                        di.icd_code LIKE '410%' OR -- Acute myocardial infarction
                        di.icd_code LIKE '411%' OR -- Other acute and subacute forms of ischemic heart disease
                        di.icd_code LIKE '413%'    -- Angina pectoris
                    ))
                )
        )
),
-- Step 2: Identify initial high-sensitivity Troponin T values for the ACS cohort
initial_troponin_values AS (
    SELECT
        aac.hadm_id,
        le.valuenum AS troponin_value_ng_ml,
        -- Rank lab events by charttime for each admission to find the initial one
        ROW_NUMBER() OVER (PARTITION BY aac.hadm_id ORDER BY le.charttime, le.labevent_id) AS rn
    FROM
        admissions_acs_cohort aac
    JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON aac.subject_id = le.subject_id AND aac.hadm_id = le.hadm_id
    WHERE
        -- Itemid for 'Troponin T, High Sensitivity' (itemid 52520 confirmed from d_labitems)
        le.itemid = 52520
        AND le.valuenum IS NOT NULL
        -- Ensure the value is in ng/mL as specified in the question
        AND le.valueuom = 'ng/mL'
),
-- Step 3: Filter for the initial measurement and the ULN threshold
filtered_initial_troponin AS (
    SELECT
        itv.troponin_value_ng_ml
    FROM
        initial_troponin_values itv
    WHERE
        itv.rn = 1 -- Only consider the first measurement for each admission
        -- Apply the ULN threshold: greater than 99th percentile (0.014 ng/mL for hs-TnT)
        AND itv.troponin_value_ng_ml > 0.014
)
-- Step 4: Calculate the median and IQR of the filtered initial values using APPROX_QUANTILES
SELECT
    APPROX_QUANTILES(troponin_value_ng_ml, 100)[OFFSET(50)] AS median_initial_troponin_ng_ml,
    APPROX_QUANTILES(troponin_value_ng_ml, 100)[OFFSET(25)] AS q1_initial_troponin_ng_ml,
    APPROX_QUANTILES(troponin_value_ng_ml, 100)[OFFSET(75)] AS q3_initial_troponin_ng_ml
FROM
    filtered_initial_troponin;