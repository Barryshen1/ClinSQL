with subcutaneous GLP-1 starts in the first 24 hours
    SUM(agg.glp1_first_24h_flag) AS glp1_starts_first_24h,

    -- Prevalence of subcutaneous GLP-1 starts in the first 24 hours (%)
    ROUND(SUM(agg.glp1_first_24h_flag) * 100.0 / COUNT(agg.hadm_id), 2) AS prevalence_first_24h_percent,

    -- Count of admissions with subcutaneous GLP-1 starts in the final 12 hours
    SUM(agg.glp1_final_12h_flag) AS glp1_starts_final_12h,

    -- Prevalence of subcutaneous GLP-1 starts in the final 12 hours (%)
    ROUND(SUM(agg.glp1_final_12h_flag) * 100.0 / COUNT(agg.hadm_id), 2) AS prevalence_final_12h_percent
FROM
    (
        WITH cohort_admissions AS (
            SELECT
                ad.subject_id,
                ad.hadm_id,
                ad.admittime,
                ad.dischtime,
                -- Calculate age at admission: anchor_age is for anchor_year
                p.anchor_age + (EXTRACT(YEAR FROM ad.admittime) - p.anchor_year) AS age_at_admission
            FROM
                `physionet-data.mimiciv_3_1_hosp.admissions` ad
            INNER JOIN
                `physionet-data.mimiciv_3_1_hosp.patients` p
                ON ad.subject_id = p.subject_id
            WHERE
                p.gender = 'F'
                AND (p.anchor_age + (EXTRACT(YEAR FROM ad.admittime) - p.anchor_year)) BETWEEN 48 AND 58
        ),
        -- Filter for admissions with both diabetes and heart failure diagnoses
        final_cohort AS (
            SELECT
                ca.subject_id,
                ca.hadm_id,
                ca.admittime,
                ca.dischtime
            FROM
                cohort_admissions ca
            INNER JOIN
                `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
                ON ca.subject_id = di.subject_id AND ca.hadm_id = di.hadm_id
            GROUP BY
                ca.subject_id, ca.hadm_id, ca.admittime, ca.dischtime
            HAVING
                -- Check for presence of diabetes diagnosis (ICD-9: 250.x, ICD-10: E10.x, E11.x)
                MAX(CASE
                    WHEN di.icd_version = 9 AND di.icd_code LIKE '250%' THEN 1
                    WHEN di.icd_version = 10 AND (di.icd_code LIKE 'E10%' OR di.icd_code LIKE 'E11%') THEN 1
                    ELSE 0
                END) = 1
                AND
                -- Check for presence of heart failure diagnosis (ICD-9: 428.x, ICD-10: I50.x)
                MAX(CASE
                    WHEN di.icd_version = 9 AND di.icd_code LIKE '428%' THEN 1
                    WHEN di.icd_version = 10 AND di.icd_code LIKE 'I50%' THEN 1
                    ELSE 0
                END) = 1
        ),
        -- Identify subcutaneous GLP-1 prescriptions
        glp1_prescriptions AS (
            SELECT DISTINCT
                ps.subject_id,
                ps.hadm_id,
                ps.starttime
            FROM
                `physionet-data.mimiciv_3_1_hosp.prescriptions` ps
            WHERE
                (
                    ps.drug LIKE '%Semaglutide%' OR
                    ps.drug LIKE '%Dulaglutide%' OR
                    ps.drug LIKE '%Liraglutide%' OR
                    ps.drug LIKE '%Exenatide%'
                )
                AND (ps.route LIKE '%SC%' OR ps.route LIKE '%Subcutaneous%') -- Filter for subcutaneous route
        )
        -- Aggregate flags for GLP-1 starts within the specified time windows
        SELECT
            fc.hadm_id,
            -- Flag for GLP-1 start in the first 24 hours of admission
            MAX(CASE
                    WHEN gp.starttime BETWEEN fc.admittime AND DATETIME_ADD(fc.admittime, INTERVAL 24 HOUR) THEN 1
                    ELSE 0
                END) AS glp1_first_24h_flag,
            -- Flag for GLP-1 start in the final 12 hours of admission
            MAX(CASE
                    WHEN gp.starttime BETWEEN DATETIME_SUB(fc.dischtime, INTERVAL 12 HOUR) AND fc.dischtime THEN 1
                    ELSE 0
                END) AS glp1_final_12h_flag
        FROM
            final_cohort fc
        LEFT JOIN
            glp1_prescriptions gp
            ON fc.subject_id = gp.subject_id AND fc.hadm_id = gp.hadm_id
        GROUP BY
            fc.hadm_id
    ) AS agg;