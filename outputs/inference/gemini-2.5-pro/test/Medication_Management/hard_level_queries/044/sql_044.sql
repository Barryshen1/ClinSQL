WITH all_admissions_ranked AS (
    -- This CTE ranks all hospital admissions for each patient to find subsequent admissions
    SELECT
        subject_id,
        hadm_id,
        admittime,
        dischtime,
        -- Find the next admission time for this patient to check for readmission
        LEAD(admittime, 1) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),
readmission_info AS (
    -- This CTE creates a 30-day readmission flag for every admission
    SELECT
        hadm_id,
        -- Flag is 1 if the next admission is within 30 days of discharge, otherwise 0
        CASE
            WHEN DATETIME_DIFF(next_admittime, dischtime, DAY) <= 30 THEN 1
            ELSE 0
        END AS is_readmitted_30d
    FROM all_admissions_ranked
),
pe_admissions AS (
    -- This CTE identifies the primary cohort: women aged 64-74 with a PE diagnosis
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    WHERE
        -- Filter for female patients
        pat.gender = 'F'
        -- Filter for age at admission between 64 and 74
        AND (pat.anchor_age + EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) BETWEEN 64 AND 74
        -- Ensure the admission has a diagnosis for Pulmonary Embolism (PE)
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
            WHERE dx.hadm_id = adm.hadm_id
            AND (
                -- ICD-9 codes for PE
                (dx.icd_version = 9 AND dx.icd_code LIKE '415.1%')
                -- ICD-10 codes for PE
                OR (dx.icd_version = 10 AND dx.icd_code LIKE 'I26%')
            )
        )
),
med_complexity AS (
    -- This CTE calculates the medication complexity score for each admission in our cohort
    SELECT
        pe.hadm_id,
        -- The score is the count of distinct medications in the first 24 hours
        COUNT(DISTINCT pr.drug) AS med_score
    FROM pe_admissions AS pe
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
        ON pe.hadm_id = pr.hadm_id
    -- Filter for prescriptions started within the first 24 hours of admission
    WHERE pr.starttime BETWEEN pe.admittime AND DATETIME_ADD(pe.admittime, INTERVAL 24 HOUR)
    GROUP BY pe.hadm_id
),
cohort_stats AS (
    -- This CTE combines the cohort with their calculated stats (med score, LOS, readmission)
    SELECT
        pe.hadm_id,
        -- If no meds were given, med_score is 0
        COALESCE(mc.med_score, 0) AS med_score,
        -- Calculate hospital length of stay in days
        DATETIME_DIFF(pe.dischtime, pe.admittime, DAY) AS los_days,
        pe.hospital_expire_flag,
        -- Join readmission info, defaulting to 0 if no readmission
        COALESCE(ri.is_readmitted_30d, 0) AS is_readmitted_30d
    FROM pe_admissions AS pe
    -- LEFT JOIN to include patients who had 0 medications in the first 24h
    LEFT JOIN med_complexity AS mc
        ON pe.hadm_id = mc.hadm_id
    -- LEFT JOIN to attach the readmission flag to our cohort
    LEFT JOIN readmission_info AS ri
        ON pe.hadm_id = ri.hadm_id
),
cohort_tertiles AS (
    -- This CTE assigns each admission to a tertile based on its medication score
    SELECT
        hadm_id,
        med_score,
        los_days,
        hospital_expire_flag,
        is_readmitted_30d,
        -- Use NTILE to create 3 groups (tertiles) based on the med_score
        NTILE(3) OVER (ORDER BY med_score) AS med_score_tertile
    FROM cohort_stats
)
-- Final step: Aggregate results by tertile and calculate the requested metrics
SELECT
    med_score_tertile,
    COUNT(hadm_id) AS number_of_admissions,
    -- Create a string showing the min and max med score for the tertile
    CONCAT(
        CAST(MIN(med_score) AS STRING),
        ' - ',
        CAST(MAX(med_score) AS STRING)
    ) AS med_score_range,
    -- Calculate average LOS, rounded to two decimal places
    ROUND(AVG(los_days), 2) AS avg_los_days,
    -- Calculate in-hospital mortality percentage
    ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_pct,
    -- Calculate 30-day readmission percentage
    ROUND(AVG(is_readmitted_30d) * 100, 2) AS readmission_30d_pct
FROM cohort_tertiles
GROUP BY med_score_tertile
ORDER BY med_score_tertile;