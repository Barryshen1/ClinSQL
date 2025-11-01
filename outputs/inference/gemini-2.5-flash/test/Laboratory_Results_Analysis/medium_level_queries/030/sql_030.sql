WITH ami_cohort AS (
    SELECT DISTINCT
        p.subject_id,
        ad.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
        ON p.subject_id = ad.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON ad.hadm_id = di.hadm_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 64 AND 74
        -- ICD-10 codes for Acute Myocardial Infarction (AMI)
        AND (di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%')
        AND di.icd_version = 10
),
first_troponin_t AS (
    SELECT
        ac.subject_id,
        ac.hadm_id,
        le.valuenum,
        ROW_NUMBER() OVER (PARTITION BY ac.subject_id, ac.hadm_id ORDER BY le.charttime) AS rn
    FROM
        ami_cohort ac
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON ac.subject_id = le.subject_id AND ac.hadm_id = le.hadm_id
    WHERE
        le.itemid = 50993 -- Itemid for Troponin T (a common high-sensitivity troponin T in MIMIC-IV)
        AND le.valuenum IS NOT NULL
        AND le.valuenum >= 0 -- Exclude potential erroneous negative values
),
categorized_troponin AS (
    SELECT
        fct.subject_id,
        fct.hadm_id,
        fct.valuenum,
        CASE
            WHEN fct.valuenum <= 0.014 THEN 'Normal'
            WHEN fct.valuenum BETWEEN 0.015 AND 0.052 THEN 'Borderline' -- Changed to BETWEEN for clarity, although >= 0.015 AND <= 0.052 is equivalent
            WHEN fct.valuenum > 0.052 THEN 'Myocardial Injury'
            ELSE 'Uncategorized' -- Should ideally not be reached with proper filtering
        END AS troponin_category
    FROM
        first_troponin_t fct
    WHERE
        fct.rn = 1 -- Select the first Troponin T measurement for each admission
)
SELECT
    ct.troponin_category,
    COUNT(*) AS num_admissions, -- Changed from COUNT(DISTINCT (ct.subject_id, ct.hadm_id)) to COUNT(*)
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM categorized_troponin), 2) AS percentage -- Changed from COUNT(DISTINCT (subject_id, hadm_id)) to COUNT(*)
FROM
    categorized_troponin ct
GROUP BY
    ct.troponin_category
ORDER BY
    CASE ct.troponin_category
        WHEN 'Normal' THEN 1
        WHEN 'Borderline' THEN 2
        WHEN 'Myocardial Injury' THEN 3
        ELSE 4
    END;