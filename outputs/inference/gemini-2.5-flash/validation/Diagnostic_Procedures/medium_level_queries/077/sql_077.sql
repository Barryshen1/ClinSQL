WITH ultrasound_codes AS (
    -- CTE to identify relevant ICD codes for ultrasound and echocardiography
    SELECT DISTINCT
        icd_code,
        icd_version
    FROM
        `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
    WHERE
        (icd_version = 10 AND (
               icd_code LIKE 'B24%' -- Diagnostic Cardiac Ultrasound (Echocardiogram)
            OR icd_code LIKE 'B40%' -- Diagnostic Ultrasound of Head and Neck
            OR icd_code LIKE 'B44%' -- Diagnostic Ultrasound of Abdomen
            OR icd_code LIKE 'B47%' -- Diagnostic Ultrasound of Peritoneal Cavity and Retroperitoneum
            OR icd_code LIKE 'B49%' -- Diagnostic Ultrasound of Genitourinary System
            OR icd_code LIKE 'B54%' -- Diagnostic Ultrasound of Upper Extremities
            OR icd_code LIKE 'B5B%' -- Diagnostic Ultrasound of Lower Extremities
            OR icd_code LIKE 'BB4%' -- Diagnostic Ultrasound of Female Reproductive System
            OR icd_code LIKE 'BB7%' -- Diagnostic Ultrasound of Male Reproductive System
            OR icd_code LIKE 'BC4%' -- Diagnostic Ultrasound of Central Nervous System
            OR icd_code LIKE 'BC7%' -- Diagnostic Ultrasound of Peripheral Nervous System
            OR icd_code LIKE 'BD4%' -- Diagnostic Ultrasound of Circulatory System
            OR icd_code LIKE 'BD9%' -- Diagnostic Ultrasound of Hematologic and Lymphatic Systems
            OR icd_code LIKE 'BF4%' -- Diagnostic Ultrasound of Eye
            OR icd_code LIKE 'BF9%' -- Diagnostic Ultrasound of Ear, Nose, Sinus
            OR icd_code LIKE 'BG4%' -- Diagnostic Ultrasound of Respiratory System
            OR icd_code LIKE 'BT4%'  -- Diagnostic Ultrasound of Integumentary System
        ))
        OR (icd_version = 9 AND icd_code LIKE '88.7%') -- ICD-9-CM codes for various diagnostic ultrasounds
),
septic_shock_admissions AS (
    -- CTE to identify admissions with a septic shock diagnosis
    SELECT DISTINCT
        subject_id,
        hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        (icd_version = 9 AND icd_code = '78552') -- Septic Shock (ICD-9)
        OR (icd_version = 10 AND icd_code = 'R6521') -- Severe sepsis with septic shock (ICD-10)
),
admissions_filtered AS (
    -- CTE for admissions that meet demographic, LOS, and septic shock criteria
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
        (CASE WHEN icu.hadm_id IS NOT NULL THEN 'ICU' ELSE 'No ICU' END) AS icu_status
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN -- Filter for admissions with septic shock
        septic_shock_admissions ssa
        ON adm.subject_id = ssa.subject_id AND adm.hadm_id = ssa.hadm_id
    LEFT JOIN (SELECT DISTINCT subject_id, hadm_id FROM `physionet-data.mimiciv_3_1_icu.icustays`) icu
        ON adm.subject_id = icu.subject_id AND adm.hadm_id = icu.hadm_id
    WHERE
        pat.gender = 'F'
        AND (EXTRACT(YEAR FROM adm.admittime) - (pat.anchor_year - pat.anchor_age)) BETWEEN 57 AND 67
        AND DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 7 -- Only consider LOS 1-7 days as per the stratification
),
ultrasounds_per_admission_with_zeros AS (
    -- CTE to count ultrasounds per eligible admission, including zero for those without
    SELECT
        af.hadm_id,
        af.los_days,
        af.icu_status,
        -- Count only matching ultrasound procedures. If no match, COUNT will be 0.
        COUNT(uc.icd_code) AS num_ultrasounds
    FROM
        admissions_filtered af
    LEFT JOIN -- Use LEFT JOIN to keep all eligible admissions, even if they had no procedures
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
        ON af.subject_id = proc.subject_id AND af.hadm_id = proc.hadm_id
    LEFT JOIN -- Use LEFT JOIN to count if the procedure is an ultrasound. COUNT(uc.icd_code) handles NULLs.
        ultrasound_codes uc
        ON proc.icd_code = uc.icd_code AND proc.icd_version = uc.icd_version
    GROUP BY
        af.hadm_id, af.los_days, af.icu_status
)
-- Final aggregation and percentile calculation
SELECT
    upa.icu_status,
    CASE
        WHEN upa.los_days BETWEEN 1 AND 3 THEN 'LOS 1-3 days'
        WHEN upa.los_days BETWEEN 4 AND 7 THEN 'LOS 4-7 days'
        ELSE 'Other LOS' -- Should not be reached due to previous filtering, but good for robustness
    END AS los_category,
    COUNT(upa.hadm_id) AS num_admissions,
    MIN(upa.num_ultrasounds) AS min_ultrasounds_per_admission,
    -- Use APPROX_QUANTILES for percentile calculation in BigQuery
    APPROX_QUANTILES(upa.num_ultrasounds, 4)[OFFSET(1)] AS p25_ultrasounds_per_admission,
    APPROX_QUANTILES(upa.num_ultrasounds, 4)[OFFSET(2)] AS p50_ultrasounds_per_admission,
    APPROX_QUANTILES(upa.num_ultrasounds, 4)[OFFSET(3)] AS p75_ultrasounds_per_admission,
    MAX(upa.num_ultrasounds) AS max_ultrasounds_per_admission
FROM
    ultrasounds_per_admission_with_zeros upa
GROUP BY
    upa.icu_status,
    los_category
ORDER BY
    upa.icu_status,
    los_category;