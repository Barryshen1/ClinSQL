WITH TargetCohort AS (
    -- Step 1: Identify male patients aged 79-89
    SELECT
        ad.subject_id,
        ad.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ad.subject_id = p.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 79 AND 89 -- Age at anchor_year
),
AcsAdmissions AS (
    -- Step 2: Filter for admissions with Acute Coronary Syndrome (ACS) diagnoses
    SELECT DISTINCT
        tc.subject_id,
        tc.hadm_id
    FROM
        TargetCohort tc
    JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON tc.hadm_id = di.hadm_id
    WHERE
        (
            di.icd_version = 10 AND
            (
                STARTS_WITH(di.icd_code, 'I20') OR -- Angina Pectoris (e.g., I20.0 unstable angina)
                STARTS_WITH(di.icd_code, 'I21') OR -- Acute myocardial infarction
                STARTS_WITH(di.icd_code, 'I22') OR -- Subsequent myocardial infarction
                STARTS_WITH(di.icd_code, 'I24')    -- Other acute ischemic heart diseases
            )
        )
        OR
        (
            di.icd_version = 9 AND
            (
                STARTS_WITH(di.icd_code, '410') OR -- Acute myocardial infarction
                STARTS_WITH(di.icd_code, '411')    -- Other acute and subacute forms of ischemic heart disease (e.g., 411.1 unstable angina)
            )
        )
),
FirstTroponinT AS (
    -- Step 3: Get the initial Troponin T measurement for each eligible admission
    SELECT
        acs.subject_id,
        acs.hadm_id,
        le.valuenum,
        le.charttime,
        ROW_NUMBER() OVER (PARTITION BY acs.subject_id, acs.hadm_id ORDER BY le.charttime) AS rn
    FROM
        AcsAdmissions acs
    JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON acs.subject_id = le.subject_id AND acs.hadm_id = le.hadm_id
    WHERE
        le.itemid = 51427 -- itemid for Troponin T
        AND le.valuenum IS NOT NULL -- Exclude null values
        AND le.valueuom = 'ng/mL' -- Ensure unit consistency
),
CategorizedTroponin AS (
    -- Step 4: Categorize the initial Troponin T levels
    SELECT
        fth.hadm_id,
        fth.valuenum,
        CASE
            WHEN fth.valuenum <= 0.01 THEN 'Normal' -- Example threshold (e.g., upper limit of normal for sensitive assays)
            WHEN fth.valuenum > 0.01 AND fth.valuenum <= 0.04 THEN 'Borderline' -- Example indeterminate zone
            WHEN fth.valuenum > 0.04 THEN 'Elevated' -- Example threshold for myocardial injury/MI
            ELSE 'Other/Unknown' -- Should not occur if valuenum is not null
        END AS troponin_t_category
    FROM
        FirstTroponinT fth
    WHERE
        fth.rn = 1
)
-- Step 5: Calculate counts and percentages
SELECT
    troponin_t_category,
    COUNT(hadm_id) AS admission_count,
    ROUND(COUNT(hadm_id) * 100.0 / SUM(COUNT(hadm_id)) OVER (), 2) AS percentage
FROM
    CategorizedTroponin
GROUP BY
    troponin_t_category
ORDER BY
    CASE troponin_t_category
        WHEN 'Normal' THEN 1
        WHEN 'Borderline' THEN 2
        WHEN 'Elevated' THEN 3
        ELSE 4
    END;