WITH admissions_cohort AS (
    SELECT
        p.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) AS los_hours,
        (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) AS age_at_admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON p.subject_id = adm.subject_id
    WHERE
        p.gender = 'M'
        AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 58 AND 68
        AND DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) >= 72
),
-- Step 2: Filter admissions_cohort for patients with T2DM and Heart Failure diagnoses.
-- An admission is included if it has at least one T2DM code AND at least one HF code.
cohort_diagnoses AS (
    SELECT
        ac.subject_id,
        ac.hadm_id,
        ac.admittime,
        ac.dischtime,
        ac.los_hours
    FROM
        admissions_cohort AS ac
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dicd
        ON ac.subject_id = dicd.subject_id AND ac.hadm_id = dicd.hadm_id
    GROUP BY
        ac.subject_id, ac.hadm_id, ac.admittime, ac.dischtime, ac.los_hours
    HAVING
        -- Condition for Type 2 Diabetes Mellitus (T2DM)
        COUNT(DISTINCT CASE
            WHEN (dicd.icd_version = 10 AND dicd.icd_code LIKE 'E11%')
            OR (dicd.icd_version = 9 AND dicd.icd_code IN ( -- Specific common ICD-9 codes for T2DM without decimals
                '25000', '25002', '25010', '25012', '25020', '25022',
                '25030', '25032', '25040', '25042', '25050', '25052',
                '25060', '25062', '25070', '25072', '25080', '25082',
                '25090', '25092'
            )) THEN dicd.icd_code END
            ) >= 1
        -- Condition for Heart Failure (HF)
        AND COUNT(DISTINCT CASE
            WHEN (dicd.icd_version = 10 AND dicd.icd_code LIKE 'I50%')
            OR (dicd.icd_version = 9 AND dicd.icd_code LIKE '428%') THEN dicd.icd_code END
            ) >= 1
),
-- Step 3: Identify the first GLP-1 agonist prescription time for each relevant admission
glp1_prescriptions AS (
    SELECT
        pr.subject_id,
        pr.hadm_id,
        MIN(pr.starttime) AS first_glp1_prescription_time
    FROM
        `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    WHERE
        LOWER(pr.drug) LIKE ('%exenatide%') OR LOWER(pr.drug) LIKE ('%byetta%') OR LOWER(pr.drug) LIKE ('%bydureon%') OR
        LOWER(pr.drug) LIKE ('%liraglutide%') OR LOWER(pr.drug) LIKE ('%victoza%') OR LOWER(pr.drug) LIKE ('%saxenda%') OR
        LOWER(pr.drug) LIKE ('%dulaglutide%') OR LOWER(pr.drug) LIKE ('%trulicity%') OR
        LOWER(pr.drug) LIKE ('%semaglutide%') OR LOWER(pr.drug) LIKE ('%ozempic%') OR LOWER(pr.drug) LIKE ('%rybelsus%') OR LOWER(pr.drug) LIKE ('%wegovy%') OR
        LOWER(pr.drug) LIKE ('%lixisenatide%') OR LOWER(pr.drug) LIKE ('%adlyxin%') OR
        LOWER(pr.drug) LIKE ('%albiglutide%') OR LOWER(pr.drug) LIKE ('%tanzeum%') OR
        LOWER(pr.drug) LIKE ('%tirzepatide%') OR LOWER(pr.drug) LIKE ('%mounjaro%') OR LOWER(pr.drug) LIKE ('%zepbound%')
    GROUP BY
        pr.subject_id, pr.hadm_id
)
-- Step 4: Combine all information and calculate the requested metrics
SELECT
    total_cohort_admissions,
    first_72h_initiation_count,
    final_12h_initiation_count,
    ROUND(first_72h_initiation_count * 100.0 / total_cohort_admissions, 2) AS percent_first_72h,
    ROUND(final_12h_initiation_count * 100.0 / total_cohort_admissions, 2) AS percent_final_12h,
    ROUND(
        ABS((first_72h_initiation_count * 100.0 / total_cohort_admissions) - (final_12h_initiation_count * 100.0 / total_cohort_admissions)),
        2
    ) AS absolute_difference_percentage_points
FROM (
    SELECT
        COUNT(DISTINCT cd.hadm_id) AS total_cohort_admissions,
        COUNT(DISTINCT CASE
            -- Check if the first GLP-1 prescription occurred within the first 72 hours of admission
            WHEN gp.first_glp1_prescription_time IS NOT NULL AND
                 gp.first_glp1_prescription_time >= cd.admittime AND
                 gp.first_glp1_prescription_time < DATETIME_ADD(cd.admittime, INTERVAL 72 HOUR)
            THEN cd.hadm_id END) AS first_72h_initiation_count,
        COUNT(DISTINCT CASE
            -- Check if the first GLP-1 prescription occurred within the final 12 hours of admission
            WHEN gp.first_glp1_prescription_time IS NOT NULL AND
                 gp.first_glp1_prescription_time >= DATETIME_SUB(cd.dischtime, INTERVAL 12 HOUR) AND
                 gp.first_glp1_prescription_time <= cd.dischtime
            THEN cd.hadm_id END) AS final_12h_initiation_count
    FROM
        cohort_diagnoses AS cd
    LEFT JOIN
        glp1_prescriptions AS gp
        ON cd.subject_id = gp.subject_id AND cd.hadm_id = gp.hadm_id
);