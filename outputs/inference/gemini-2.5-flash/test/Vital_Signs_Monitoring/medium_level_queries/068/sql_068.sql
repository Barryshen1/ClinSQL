WITH eligible_icu_patients AS (
        SELECT
            p.subject_id,
            adm.hadm_id,
            ie.stay_id,
            -- Determine if the patient had any stroke diagnosis during this specific admission
            MAX(CASE
                WHEN di.icd_version = 9 AND di.icd_code BETWEEN '430' AND '43899' THEN 1 -- ICD-9 stroke codes (starting with 430-438)
                WHEN di.icd_version = 10 AND di.icd_code BETWEEN 'I60' AND 'I6999' THEN 1 -- ICD-10 stroke codes (starting with I60-I69)
                ELSE 0
            END) AS has_stroke
        FROM
            `physionet-data.mimiciv_3_1_hosp`.patients p
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp`.admissions adm
            ON p.subject_id = adm.subject_id
        INNER JOIN
            `physionet-data.mimiciv_3_1_icu`.icustays ie
            ON adm.hadm_id = ie.hadm_id
        LEFT JOIN
            `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
            ON adm.hadm_id = di.hadm_id AND p.subject_id = di.subject_id
        WHERE
            p.gender = 'F'
            AND p.anchor_age BETWEEN 41 AND 51 -- Age at first admission
        GROUP BY
            p.subject_id, adm.hadm_id, ie.stay_id
    ),
    -- CTE 2: Retrieve and categorize Mean Arterial Pressure (MAP) measurements for the eligible population
    map_measurements AS (
        SELECT
            ce.subject_id,
            ce.hadm_id,
            ce.stay_id,
            ce.valuenum AS map_value,
            CASE
                WHEN ce.valuenum IS NULL OR ce.valuenum <= 0 THEN 'Invalid MAP'
                WHEN ce.valuenum < 65 THEN '<65 mmHg'
                WHEN ce.valuenum >= 65 AND ce.valuenum < 75 THEN '65-74 mmHg'
                WHEN ce.valuenum >= 75 AND ce.valuenum < 85 THEN '75-84 mmHg'
                WHEN ce.valuenum >= 85 THEN '>=85 mmHg'
                ELSE 'Other/Unknown'
            END AS map_category
        FROM
            `physionet-data.mimiciv_3_1_icu`.chartevents ce
        WHERE
            ce.itemid = 220056 -- Itemid for 'Arterial Blood Pressure mean' (MAP)
            AND ce.valuenum IS NOT NULL
            AND ce.valuenum > 0 -- Ensure valid, positive MAP readings
    ),
    -- CTE 3: Link eligible patients with their distinct MAP categories and stroke status
    -- A patient can appear in multiple MAP categories if their MAP values fluctuated
    patient_map_category_link AS (
        SELECT DISTINCT
            ep.subject_id,
            mm.map_category,
            ep.has_stroke
        FROM
            eligible_icu_patients ep
        INNER JOIN
            map_measurements mm
            ON ep.subject_id = mm.subject_id
            AND ep.hadm_id = mm.hadm_id
            AND ep.stay_id = mm.stay_id
        WHERE
            mm.map_category != 'Invalid MAP' AND mm.map_category != 'Other/Unknown' -- Filter out any non-categorized MAP readings
    )
    -- Final aggregation: Calculate patient counts and stroke rates per MAP category
    SELECT
        pmcl.map_category,
        COUNT(DISTINCT pmcl.subject_id) AS patient_count,
        COUNT(DISTINCT CASE WHEN pmcl.has_stroke = 1 THEN pmcl.subject_id END) AS stroke_patient_count,
        ROUND(
            (CAST(COUNT(DISTINCT CASE WHEN pmcl.has_stroke = 1 THEN pmcl.subject_id END) AS BIGNUMERIC) /
             CAST(COUNT(DISTINCT pmcl.subject_id) AS BIGNUMERIC)) * 100,
            2
        ) AS stroke_rate_percent
    FROM
        patient_map_category_link pmcl
    GROUP BY
        pmcl.map_category
    ORDER BY
        -- Custom ordering for MAP categories for better readability
        CASE
            WHEN pmcl.map_category = '<65 mmHg' THEN 1
            WHEN pmcl.map_category = '65-74 mmHg' THEN 2
            WHEN pmcl.map_category = '75-84 mmHg' THEN 3
            WHEN pmcl.map_category = '>=85 mmHg' THEN 4
            ELSE 5 -- Fallback for any unexpected categories
        END;