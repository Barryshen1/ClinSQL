WITH
-- 1. Define the cohort of interest: female inpatients aged 68-78
cohort AS (
    SELECT
        adm.hadm_id,
        adm.admittime,
        adm.dischtime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    WHERE
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 68 AND 78
        AND adm.dischtime IS NOT NULL -- Ensure dischtime is available for "last 12h" calculation
        AND adm.dischtime > adm.admittime -- Basic data quality check
),

-- 2. Define the drug classes to ensure all are included in the final report
drug_list AS (
    SELECT 'Metformin' AS drug_class UNION ALL
    SELECT 'Sulfonylureas' AS drug_class UNION ALL
    SELECT 'DPP-4 Inhibitors' AS drug_class UNION ALL
    SELECT 'SGLT2 Inhibitors' AS drug_class
),

-- 3. Identify categorized medication administrations for the cohort
med_events AS (
    SELECT
        c.hadm_id,
        c.admittime,
        c.dischtime,
        emar.charttime,
        CASE
            WHEN LOWER(emar.medication) LIKE '%metformin%' THEN 'Metformin'
            WHEN LOWER(emar.medication) LIKE '%glipizide%' OR LOWER(emar.medication) LIKE '%glyburide%' OR LOWER(emar.medication) LIKE '%glimepiride%' THEN 'Sulfonylureas'
            WHEN LOWER(emar.medication) LIKE '%sitagliptin%' OR LOWER(emar.medication) LIKE '%saxagliptin%' OR LOWER(emar.medication) LIKE '%linagliptin%' OR LOWER(emar.medication) LIKE '%alogliptin%' THEN 'DPP-4 Inhibitors'
            WHEN LOWER(emar.medication) LIKE '%canagliflozin%' OR LOWER(emar.medication) LIKE '%dapagliflozin%' OR LOWER(emar.medication) LIKE '%empagliflozin%' OR LOWER(emar.medication) LIKE '%ertugliflozin%' THEN 'SGLT2 Inhibitors'
            ELSE NULL
        END AS drug_class
    FROM
        cohort AS c
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.emar` AS emar
        ON c.hadm_id = emar.hadm_id
    WHERE
        -- Restrict to administrations during the hospital stay
        emar.charttime BETWEEN c.admittime AND c.dischtime
),

-- 4. For each patient and drug class, flag if administered in the specified windows
patient_drug_exposure AS (
    SELECT
        hadm_id,
        drug_class,
        -- Flag if any administration occurred in the first 48 hours
        MAX(CASE
            WHEN charttime BETWEEN admittime AND TIMESTAMP_ADD(admittime, INTERVAL 48 HOUR) THEN 1
            ELSE 0
        END) AS given_in_first_48h,
        -- Flag if any administration occurred in the last 12 hours
        MAX(CASE
            WHEN charttime BETWEEN TIMESTAMP_SUB(dischtime, INTERVAL 12 HOUR) AND dischtime THEN 1
            ELSE 0
        END) AS given_in_last_12h
    FROM
        med_events
    WHERE
        drug_class IS NOT NULL
    GROUP BY
        hadm_id, drug_class
),

-- 5. Count the number of unique patients for each drug class in each window
final_counts AS (
    SELECT
        drug_class,
        SUM(given_in_first_48h) AS count_first_48h,
        SUM(given_in_last_12h) AS count_last_12h
    FROM
        patient_drug_exposure
    GROUP BY
        drug_class
)

-- 6. Calculate prevalence and net change, joining all pieces together
SELECT
    dl.drug_class,
    ROUND(
        COALESCE(fc.count_first_48h, 0) * 100.0 / total_admissions.count, 2
    ) AS prevalence_first_48h_pct,
    ROUND(
        COALESCE(fc.count_last_12h, 0) * 100.0 / total_admissions.count, 2
    ) AS prevalence_last_12h_pct,
    ROUND(
        (COALESCE(fc.count_last_12h, 0) * 100.0 / total_admissions.count)
        - (COALESCE(fc.count_first_48h, 0) * 100.0 / total_admissions.count), 2
    ) AS net_change_pp
FROM
    drug_list AS dl
LEFT JOIN
    final_counts AS fc
    ON dl.drug_class = fc.drug_class
CROSS JOIN
    (SELECT COUNT(DISTINCT hadm_id) AS count FROM cohort) AS total_admissions
ORDER BY
    dl.drug_class;