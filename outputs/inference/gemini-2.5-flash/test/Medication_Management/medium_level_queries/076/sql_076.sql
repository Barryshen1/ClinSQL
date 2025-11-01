WITH eligible_admissions AS (
    -- Step 1: Identify eligible admissions based on demographics and LOS
    -- Step 2: Identify admissions with Diabetes diagnosis
    -- Step 3: Identify admissions with Acute Heart Failure diagnosis
    -- Step 4: Combine all criteria to get the final cohort of eligible admissions
    WITH admissions_base AS (
        SELECT
            ad.subject_id,
            ad.hadm_id,
            ad.admittime,
            ad.dischtime,
            DATETIME_DIFF(ad.dischtime, ad.admittime, HOUR) AS los_hours
        FROM
            `physionet-data.mimiciv_3_1_hosp.admissions` ad
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.patients` pa
            ON ad.subject_id = pa.subject_id
        WHERE
            pa.gender = 'F'
            AND pa.anchor_age BETWEEN 75 AND 85
            AND ad.dischtime IS NOT NULL -- Ensure dischtime exists for valid LOS calculation
            AND DATETIME_DIFF(ad.dischtime, ad.admittime, HOUR) >= 36 -- Admission length of stay >= 36 hours
    ),
    diabetes_hadms AS (
        SELECT DISTINCT hadm_id
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        WHERE
            (
                icd_version = 9 AND icd_code LIKE '250%' -- ICD-9 codes for diabetes
            ) OR (
                icd_version = 10 AND (icd_code LIKE 'E08%' OR icd_code LIKE 'E09%' OR icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E13%') -- ICD-10 codes for diabetes
            )
    ),
    heart_failure_hadms AS (
        SELECT DISTINCT hadm_id
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        WHERE
            (
                icd_version = 9 AND icd_code LIKE '428%' -- ICD-9 codes for heart failure (e.g., 428.0 for CHF)
            ) OR (
                icd_version = 10 AND icd_code LIKE 'I50%' -- ICD-10 codes for heart failure
            )
    )
    SELECT
        ab.subject_id,
        ab.hadm_id,
        ab.admittime,
        ab.dischtime,
        ab.los_hours
    FROM
        admissions_base ab
    INNER JOIN
        diabetes_hadms dh
        ON ab.hadm_id = dh.hadm_id
    INNER JOIN
        heart_failure_hadms hfh
        ON ab.hadm_id = hfh.hadm_id
),
glp1_prescriptions AS (
    -- Step 5: Identify all injectable GLP-1 prescriptions for the eligible cohort
    SELECT
        p.subject_id,
        p.hadm_id,
        p.starttime
    FROM
        `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    INNER JOIN
        eligible_admissions ea
        ON p.subject_id = ea.subject_id AND p.hadm_id = ea.hadm_id
    WHERE
        -- Filtering for common injectable GLP-1 drug names (case-insensitive search for robustness)
        LOWER(p.drug) LIKE '%exenatide%'
        OR LOWER(p.drug) LIKE '%liraglutide%'
        OR LOWER(p.drug) LIKE '%dulaglutide%'
        OR LOWER(p.drug) LIKE '%semaglutide%'
),
admission_glp1_flags AS (
    -- For each eligible admission, determine if GLP-1 was started in the specified windows
    SELECT
        ea.hadm_id,
        -- Flag if an injectable GLP-1 was started in the first 24 hours of admission
        MAX(CASE WHEN gp.starttime >= ea.admittime AND gp.starttime < DATETIME_ADD(ea.admittime, INTERVAL 24 HOUR) THEN 1 ELSE 0 END) AS started_first_24h_flag,
        -- Flag if an injectable GLP-1 was started in the final 12 hours of admission
        MAX(CASE WHEN gp.starttime >= DATETIME_SUB(ea.dischtime, INTERVAL 12 HOUR) AND gp.starttime <= ea.dischtime THEN 1 ELSE 0 END) AS started_final_12h_flag
    FROM
        eligible_admissions ea
    LEFT JOIN
        glp1_prescriptions gp
        ON ea.subject_id = gp.subject_id AND ea.hadm_id = gp.hadm_id
    GROUP BY
        ea.hadm_id
)
-- Final step: Calculate percentages
SELECT
    SAFE_DIVIDE(SUM(started_first_24h_flag), COUNT(hadm_id)) * 100 AS percent_started_first_24h,
    SAFE_DIVIDE(SUM(started_final_12h_flag), COUNT(hadm_id)) * 100 AS percent_started_final_12h
FROM
    admission_glp1_flags;