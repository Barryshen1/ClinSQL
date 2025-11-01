WITH
-- Step 1: Define the base cohort of male patients aged 45-55 at admission.
base_cohort AS (
    SELECT
        p.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS a
        ON p.subject_id = a.subject_id
    WHERE
        p.gender = 'M'
        AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 45 AND 55
),

-- Step 2: Identify admissions with both T2DM and Heart Failure diagnoses.
diagnosed_cohort AS (
    SELECT
        hadm_id
    FROM (
        SELECT
            dia.hadm_id,
            -- Flag for T2DM diagnosis
            MAX(
                CASE
                    WHEN
                        (d.icd_version = 10 AND d.icd_code LIKE 'E11%')
                        OR (
                            d.icd_version = 9 AND (d.icd_code LIKE '250_0' OR d.icd_code LIKE '250_2')
                        )
                        THEN 1
                    ELSE 0
                END
            ) AS has_t2dm,
            -- Flag for Heart Failure diagnosis
            MAX(
                CASE
                    WHEN
                        (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
                        OR (d.icd_version = 9 AND d.icd_code LIKE '428%')
                        THEN 1
                    ELSE 0
                END
            ) AS has_hf
        FROM
            `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dia
        JOIN
            `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
            ON dia.icd_code = d.icd_code AND dia.icd_version = d.icd_version
        GROUP BY
            dia.hadm_id
    ) AS diagnoses
    WHERE
        has_t2dm = 1 AND has_hf = 1
),

-- Step 3: Combine base cohort and diagnoses to get the final patient set.
final_cohort AS (
    SELECT
        bc.subject_id,
        bc.hadm_id,
        bc.admittime,
        bc.dischtime
    FROM
        base_cohort AS bc
    JOIN
        diagnosed_cohort AS dc ON bc.hadm_id = dc.hadm_id
),

-- Step 4: Identify all GLP-1 prescriptions for the final cohort.
glp1_prescriptions AS (
    SELECT
        hadm_id,
        starttime,
        stoptime
    FROM
        `physionet-data.mimiciv_3_1_hosp.prescriptions`
    WHERE
        hadm_id IN (SELECT hadm_id FROM final_cohort)
        AND LOWER(drug) IN (
            'liraglutide', 'victoza',
            'semaglutide', 'ozempic', 'rybelsus', 'wegovy',
            'dulaglutide', 'trulicity',
            'exenatide', 'byetta', 'bydureon',
            'lixisenatide', 'adlyxin',
            'tirzepatide', 'mounjaro'
        )
),

-- Step 5: For each patient in the cohort, flag if they meet the time-based criteria.
cohort_with_flags AS (
    SELECT
        fc.hadm_id,
        -- Flag if any GLP-1 prescription started within 72h of admission
        MAX(
            CASE
                WHEN
                    glp1.starttime IS NOT NULL
                    AND DATETIME_DIFF(glp1.starttime, fc.admittime, HOUR) BETWEEN 0 AND 72
                    THEN 1
                ELSE 0
            END
        ) AS started_glp1_within_72h,
        -- Flag if any GLP-1 prescription was active in the last 48h of the stay
        MAX(
            CASE
                WHEN
                    glp1.starttime IS NOT NULL AND fc.dischtime IS NOT NULL
                    -- Check for overlap: [start1, end1] overlaps [start2, end2] if start1 <= end2 and end1 >= start2
                    AND glp1.starttime <= fc.dischtime
                    AND COALESCE(glp1.stoptime, fc.dischtime)
                    >= DATETIME_SUB(fc.dischtime, INTERVAL 48 HOUR)
                    THEN 1
                ELSE 0
            END
        ) AS on_glp1_last_48h
    FROM
        final_cohort AS fc
    LEFT JOIN
        glp1_prescriptions AS glp1 ON fc.hadm_id = glp1.hadm_id
    GROUP BY
        fc.hadm_id
)

-- Step 6: Calculate the final percentages and net change.
SELECT
    COUNT(hadm_id) AS total_patients_in_cohort,
    ROUND(
        100.0 * SUM(started_glp1_within_72h) / COUNT(hadm_id), 2
    ) AS pct_started_on_glp1_within_72h,
    ROUND(
        100.0 * SUM(on_glp1_last_48h) / COUNT(hadm_id), 2
    ) AS pct_on_glp1_in_last_48h,
    ROUND(
        (100.0 * SUM(on_glp1_last_48h) / COUNT(hadm_id))
        - (100.0 * SUM(started_glp1_within_72h) / COUNT(hadm_id)), 2
    ) AS net_change_pct
FROM
    cohort_with_flags;