WITH PatientFilter AS (
    -- Step 1: Filter for male patients aged 59-69
    SELECT
        p.subject_id,
        p.gender,
        p.anchor_age
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 59 AND 69
),
ACS_Admissions AS (
    -- Step 2 & 3: Identify ACS admissions and determine if ACS is primary or secondary
    -- Also calculate LOS and filter for the specified range (1-7 days)
    SELECT
        ad.subject_id,
        ad.hadm_id,
        DATE_DIFF(ad.dischtime, ad.admittime, DAY) AS los_days,
        -- Find the minimum sequence number among *all* ACS diagnoses for this admission.
        -- If it's 1, then ACS was a primary diagnosis. Otherwise, it's secondary.
        MIN(CASE
                WHEN di.icd_code = 'I200' -- Unstable angina (ICD-10, stored as I200 in MIMIC-IV)
                OR STARTS_WITH(di.icd_code, 'I21') -- Acute Myocardial Infarction
                OR STARTS_WITH(di.icd_code, 'I22') -- Subsequent Myocardial Infarction
                OR di.icd_code = 'I249' -- Acute ischemic heart disease, unspecified
                THEN di.seq_num
            END) AS min_acs_seq_num_for_admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    INNER JOIN
        PatientFilter pf
        ON ad.subject_id = pf.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON ad.hadm_id = di.hadm_id
    WHERE
        di.icd_version = 10 -- Ensure using ICD-10 codes
        AND (
               di.icd_code = 'I200'
            OR STARTS_WITH(di.icd_code, 'I21')
            OR STARTS_WITH(di.icd_code, 'I22')
            OR di.icd_code = 'I249'
            )
    GROUP BY
        ad.subject_id, ad.hadm_id, ad.dischtime, ad.admittime
    HAVING
        -- Ensure the admission actually has an ACS diagnosis within the filtered set
        MIN(CASE
                WHEN di.icd_code = 'I200'
                OR STARTS_WITH(di.icd_code, 'I21')
                OR STARTS_WITH(di.icd_code, 'I22')
                OR di.icd_code = 'I249'
                THEN di.seq_num
            END) IS NOT NULL
        -- Filter LOS early to narrow down the dataset
        AND DATE_DIFF(ad.dischtime, ad.admittime, DAY) BETWEEN 1 AND 7
),
AdmissionCategories AS (
    -- Step 4: Categorize admissions by LOS and ACS diagnosis type
    SELECT
        hadm_id,
        CASE
            WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
            WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
            -- No ELSE needed as LOS is already filtered in ACS_Admissions
        END AS los_category,
        CASE
            WHEN min_acs_seq_num_for_admission = 1 THEN 'Primary ACS'
            ELSE 'Secondary ACS'
        END AS acs_diagnosis_type
    FROM
        ACS_Admissions
),
ProcedureCounts AS (
    -- Step 5: Count diagnostic procedures per eligible admission
    SELECT
        ac.hadm_id,
        ac.los_category,
        ac.acs_diagnosis_type,
        COUNT(DISTINCT pi.icd_code) AS procedure_count -- Count distinct ICD procedure codes
    FROM
        AdmissionCategories ac
    LEFT JOIN -- Use LEFT JOIN to include admissions with 0 procedures
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
        ON ac.hadm_id = pi.hadm_id
    GROUP BY
        ac.hadm_id, ac.los_category, ac.acs_diagnosis_type
)
-- Step 6: Calculate quantiles based on the specified stratifications
SELECT
    los_category,
    acs_diagnosis_type,
    APPROX_QUANTILES(procedure_count, 100)[OFFSET(25)] AS p25_procedures,
    APPROX_QUANTILES(procedure_count, 100)[OFFSET(50)] AS p50_procedures,
    APPROX_QUANTILES(procedure_count, 100)[OFFSET(75)] AS p75_procedures
FROM
    ProcedureCounts
GROUP BY
    los_category,
    acs_diagnosis_type
ORDER BY
    los_category,
    acs_diagnosis_type;