WITH initial_troponin_data AS (
    SELECT
        p.subject_id,
        ad.hadm_id,
        le.charttime,
        le.valuenum,
        CASE
            -- Example cutoffs for high-sensitivity Troponin T (hs-TnT) in ng/mL or ug/L
            -- These ranges may vary based on assay and clinical guidelines.
            WHEN le.valuenum < 0.014 THEN 'Normal'
            WHEN le.valuenum >= 0.014 AND le.valuenum <= 0.05 THEN 'Borderline'
            WHEN le.valuenum > 0.05 THEN 'Elevated'
            ELSE 'Unknown' -- Fallback for unexpected values, though filtered by IS NOT NULL
        END AS troponin_category
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
        ON p.subject_id = ad.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON ad.hadm_id = di.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON p.subject_id = le.subject_id AND ad.hadm_id = le.hadm_id
    WHERE
        p.gender = 'F' -- Filter for female patients
        AND p.anchor_age BETWEEN 40 AND 50 -- Filter for age 40-50
        AND (
            (di.icd_version = 10 AND di.icd_code LIKE 'I21%') OR -- ICD-10 codes for AMI
            (di.icd_version = 9 AND di.icd_code LIKE '410%')    -- ICD-9 codes for AMI
        )
        -- Filter for Troponin T lab item (itemid 51002 is commonly Troponin T, label 'Troponin T')
        AND le.itemid = 51002
        AND le.valuenum IS NOT NULL -- Ensure numeric value exists
        -- Consider only common units for Troponin T (ug/L is often equivalent to ng/mL)
        AND le.valueuom IN ('ug/L', 'ng/mL')
    -- Get the earliest Troponin T measurement for each admission
    QUALIFY ROW_NUMBER() OVER (PARTITION BY le.subject_id, le.hadm_id ORDER BY le.charttime ASC) = 1
)
SELECT
    troponin_category,
    COUNT(*) AS patient_count
FROM
    initial_troponin_data
GROUP BY
    troponin_category
ORDER BY
    CASE troponin_category
        WHEN 'Normal' THEN 1
        WHEN 'Borderline' THEN 2
        WHEN 'Elevated' THEN 3
        ELSE 4 -- For 'Unknown' or any other unexpected category
    END;