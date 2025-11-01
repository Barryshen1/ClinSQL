WITH
-- Step 1: Identify hospital admissions with a diagnosis of Type 2 Diabetes Mellitus (T2DM)
t2dm_hadms AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        -- ICD-10 codes for Type 2 Diabetes Mellitus start with E11
        (icd_version = 10 AND icd_code LIKE 'E11%') OR
        -- ICD-9 codes for Type 2 Diabetes Mellitus are 250.x0 and 250.x2
        -- The 4th character is a '.', so the 5th character is the specific digit.
        (icd_version = 9 AND icd_code LIKE '250%' AND (SUBSTR(icd_code, 5, 1) = '0' OR SUBSTR(icd_code, 5, 1) = '2'))
),

-- Step 2: Identify hospital admissions with a diagnosis of Heart Failure
hf_hadms AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        -- ICD-9 codes for Heart Failure start with 428
        (icd_version = 9 AND icd_code LIKE '428%') OR
        -- ICD-10 codes for Heart Failure start with I50
        (icd_version = 10 AND icd_code LIKE 'I50%')
),

-- Step 3: Define the primary patient cohort based on demographics and diagnoses
final_cohort AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    -- Join to get patient demographics
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    -- Inner join to include only patients with T2DM
    INNER JOIN t2dm_hadms
        ON adm.hadm_id = t2dm_hadms.hadm_id
    -- Inner join to include only patients with Heart Failure
    INNER JOIN hf_hadms
        ON adm.hadm_id = hf_hadms.hadm_id
    WHERE
        -- Filter for males aged 52-62
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 52 AND 62
        -- Ensure admission and discharge times are available to define the windows
        AND adm.admittime IS NOT NULL
        AND adm.dischtime IS NOT NULL
),

-- Step 4: Identify all administrations of injectable GLP-1 agonists
glp1_admins AS (
    SELECT DISTINCT
        emar.hadm_id,
        emar.charttime
    FROM `physionet-data.mimiciv_3_1_hosp.emar` AS emar
    -- Join to get route information to confirm the medication is injectable
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` AS ed
        ON emar.subject_id = ed.subject_id
        AND emar.emar_id = ed.emar_id
        AND emar.emar_seq = ed.emar_seq
    WHERE
        (
            -- Generic and brand names for GLP-1s
            LOWER(emar.medication) LIKE '%semaglutide%' OR LOWER(emar.medication) LIKE '%ozempic%' OR LOWER(emar.medication) LIKE '%wegovy%'
            OR LOWER(emar.medication) LIKE '%liraglutide%' OR LOWER(emar.medication) LIKE '%victoza%' OR LOWER(emar.medication) LIKE '%saxenda%'
            OR LOWER(emar.medication) LIKE '%dulaglutide%' OR LOWER(emar.medication) LIKE '%trulicity%'
            OR LOWER(emar.medication) LIKE '%exenatide%' OR LOWER(emar.medication) LIKE '%byetta%' OR LOWER(emar.medication) LIKE '%bydureon%'
            OR LOWER(emar.medication) LIKE '%lixisenatide%' OR LOWER(emar.medication) LIKE '%adlyxin%'
        )
        -- Filter for common injectable routes. 'SC' (Subcutaneous) is the most frequent.
        AND ed.route IN ('SC', 'IV', 'IM')
),

-- Step 5: For each patient in the cohort, flag if they received a GLP-1 in the specified windows
treatment_flags AS (
    SELECT
        fc.hadm_id,
        -- Flag for administration in the first 24 hours of admission
        MAX(
            CASE
                WHEN ga.charttime BETWEEN fc.admittime AND DATETIME_ADD(fc.admittime, INTERVAL 24 HOUR)
                THEN 1
                ELSE 0
            END
        ) AS received_first_24h,
        -- Flag for administration in the final 48 hours of admission
        MAX(
            CASE
                WHEN ga.charttime BETWEEN DATETIME_SUB(fc.dischtime, INTERVAL 48 HOUR) AND fc.dischtime
                THEN 1
                ELSE 0
            END
        ) AS received_final_48h
    FROM final_cohort AS fc
    -- Left join to keep all cohort patients, even those without GLP-1 administrations
    LEFT JOIN glp1_admins AS ga
        ON fc.hadm_id = ga.hadm_id
    GROUP BY fc.hadm_id
)

-- Step 6: Calculate final prevalence, absolute change, and relative change
SELECT
    COUNT(*) AS total_patients_in_cohort,
    SUM(received_first_24h) AS patients_on_glp1_first_24h,
    SUM(received_final_48h) AS patients_on_glp1_final_48h,
    
    -- Calculate prevalence percentages
    ROUND(SAFE_DIVIDE(SUM(received_first_24h) * 100.0, COUNT(*)), 2) AS prevalence_first_24h_pct,
    ROUND(SAFE_DIVIDE(SUM(received_final_48h) * 100.0, COUNT(*)), 2) AS prevalence_final_48h_pct,
    
    -- Calculate absolute change in percentage points
    ROUND(
        (SAFE_DIVIDE(SUM(received_final_48h) * 100.0, COUNT(*))) -
        (SAFE_DIVIDE(SUM(received_first_24h) * 100.0, COUNT(*))),
    2) AS absolute_change_pct_points,
    
    -- Calculate relative change as a percentage
    ROUND(
        SAFE_DIVIDE(
            (SAFE_DIVIDE(SUM(received_final_48h), COUNT(*)) - SAFE_DIVIDE(SUM(received_first_24h), COUNT(*))),
            NULLIF(SAFE_DIVIDE(SUM(received_first_24h), COUNT(*)), 0)
        ) * 100.0,
    2) AS relative_change_pct
FROM treatment_flags;