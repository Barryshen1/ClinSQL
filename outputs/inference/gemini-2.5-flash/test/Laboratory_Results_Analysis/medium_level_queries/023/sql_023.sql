WITH cohort_admissions AS (
    SELECT
        a.subject_id,
        a.hadm_id,
        -- Calculate age at admission
        p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
        a.admittime,
        a.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 67 AND 77
    AND EXISTS ( -- Check for ACS diagnosis (Acute Myocardial Infarction as primary indicator)
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        WHERE di.hadm_id = a.hadm_id
        AND (
               (di.icd_version = 9 AND di.icd_code LIKE '410%') -- ICD-9 for Acute myocardial infarction
            OR (di.icd_version = 10 AND di.icd_code LIKE 'I21%') -- ICD-10 for Acute myocardial infarction
        )
    )
),
-- Step 2: Get the first Troponin T measurement for each admission in the cohort
first_troponin_t_measurements AS (
    SELECT
        le.hadm_id,
        le.valuenum AS initial_troponin_t_value,
        ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime, le.labevent_id) AS rn
    FROM
        `physionet-data.mimiciv_3_1_hosp.labevents` le
    INNER JOIN
        cohort_admissions ca
        ON le.hadm_id = ca.hadm_id
    WHERE
        le.itemid = 51003 -- Itemid for Troponin T (found in d_labitems)
        AND le.valuenum IS NOT NULL -- Ensure a numeric value exists
),
final_troponin_t_values AS (
  SELECT
      ftt.hadm_id,
      ftt.initial_troponin_t_value
  FROM
      first_troponin_t_measurements ftt
  WHERE
      ftt.rn = 1
),
-- Step 3: Categorize Troponin T levels for the cohort
categorized_admissions_with_troponin AS (
    SELECT
        ca.subject_id,
        ca.hadm_id,
        ca.hospital_expire_flag,
        fttv.initial_troponin_t_value,
        CASE
            WHEN fttv.initial_troponin_t_value <= 0.04 THEN 'Normal'
            WHEN fttv.initial_troponin_t_value > 0.04 AND fttv.initial_troponin_t_value <= 0.1 THEN 'Borderline'
            WHEN fttv.initial_troponin_t_value > 0.1 THEN 'Elevated'
            ELSE 'Unknown_Category' -- This case should ideally not be hit with NOT NULL valuenum
        END AS troponin_category
    FROM
        cohort_admissions ca
    INNER JOIN -- Use INNER JOIN to only include admissions that have an initial Troponin T measurement
        final_troponin_t_values fttv
        ON ca.hadm_id = fttv.hadm_id
)
-- Step 4: Aggregate results by Troponin T category
SELECT
    troponin_category,
    COUNT(DISTINCT hadm_id) AS num_admissions,
    SUM(hospital_expire_flag) AS num_deaths,
    SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(DISTINCT hadm_id)) * 100 AS mortality_rate_percent,
    (COUNT(DISTINCT hadm_id) / (SELECT COUNT(DISTINCT hadm_id) FROM categorized_admissions_with_troponin)) * 100 AS percent_of_total_admissions_in_cohort
FROM
    categorized_admissions_with_troponin
GROUP BY
    troponin_category
ORDER BY
    -- Order by category based on clinical relevance: Normal, Borderline, Elevated
    CASE troponin_category
        WHEN 'Normal' THEN 1
        WHEN 'Borderline' THEN 2
        WHEN 'Elevated' THEN 3
        ELSE 4
    END
;