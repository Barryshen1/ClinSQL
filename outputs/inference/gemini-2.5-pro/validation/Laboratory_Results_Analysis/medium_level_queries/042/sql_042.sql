WITH cohort AS (
    -- Step 1: Identify female patients aged 84-94 admitted with chest pain
    SELECT
        a.subject_id,
        a.hadm_id,
        a.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS a
        ON p.subject_id = a.subject_id
    -- Restrict to admissions with a diagnosis of chest pain
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        ON a.hadm_id = dx.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
        ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
    WHERE
        p.gender = 'F'
        -- Calculate age at admission and filter for the 84-94 range
        AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 84 AND 94
        AND LOWER(d_dx.long_title) LIKE '%chest pain%'
    GROUP BY -- Use GROUP BY to get distinct admissions
        a.subject_id, a.hadm_id, a.hospital_expire_flag
),
first_troponin AS (
    -- Step 2: Find the first Troponin T measurement for each admission
    SELECT
        hadm_id,
        valuenum
    FROM (
        SELECT
            hadm_id,
            valuenum,
            ROW_NUMBER() OVER(PARTITION BY hadm_id ORDER BY charttime ASC) AS rn
        FROM
            `physionet-data.mimiciv_3_1_hosp.labevents`
        WHERE
            itemid = 51003 -- 51003 is the itemid for 'Troponin T'
            AND valuenum IS NOT NULL
            AND valueuom = 'ng/mL' -- Ensure consistent units for comparison
    ) AS ranked_labs
    WHERE rn = 1
),
categorized_patients AS (
    -- Step 3: Join the cohort with their first troponin and categorize the result
    SELECT
        c.hadm_id,
        c.hospital_expire_flag,
        CASE
            WHEN ft.valuenum < 0.01 THEN 'Normal'
            WHEN ft.valuenum BETWEEN 0.01 AND 0.04 THEN 'Borderline'
            WHEN ft.valuenum > 0.04 THEN 'Elevated'
            ELSE NULL -- Should not happen due to valuenum IS NOT NULL filter
        END AS troponin_category
    FROM
        cohort AS c
    INNER JOIN
        first_troponin AS ft
        ON c.hadm_id = ft.hadm_id
)
-- Step 4: Aggregate results to get counts, percentages, and mortality for each category
SELECT
    troponin_category,
    COUNT(hadm_id) AS number_of_patients,
    ROUND(100.0 * COUNT(hadm_id) / SUM(COUNT(hadm_id)) OVER(), 2) AS percentage_of_total_patients,
    ROUND(100.0 * AVG(hospital_expire_flag), 2) AS in_hospital_mortality_percent
FROM
    categorized_patients
WHERE
    troponin_category IS NOT NULL
GROUP BY
    troponin_category
ORDER BY
    CASE
        WHEN troponin_category = 'Normal' THEN 1
        WHEN troponin_category = 'Borderline' THEN 2
        WHEN troponin_category = 'Elevated' THEN 3
    END;