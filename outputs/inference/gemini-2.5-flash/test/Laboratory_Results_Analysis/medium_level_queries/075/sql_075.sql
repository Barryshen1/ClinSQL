WITH CohortAdmissions AS (
    SELECT DISTINCT
        adm.subject_id,
        adm.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id
    WHERE
        pat.gender = 'M'
        -- Calculate age at admission: anchor_age + (admission_year - anchor_year)
        AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 41 AND 51
        AND (
            diag.icd_code LIKE 'R07%' -- Chest pain (e.g., R07.1, R07.2, R07.4)
            OR diag.icd_code LIKE 'I21%' -- Acute Myocardial Infarction (e.g., I21.0, I21.1)
        )
),
InitialTroponinT AS (
    SELECT
        le.subject_id,
        le.hadm_id,
        le.valuenum
    FROM
        `physionet-data.mimiciv_3_1_hosp.labevents` le
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
        ON le.itemid = dli.itemid
    INNER JOIN
        CohortAdmissions ca
        ON le.subject_id = ca.subject_id AND le.hadm_id = ca.hadm_id
    WHERE
        le.itemid = 51003 -- Itemid for Troponin T (verified via d_labitems)
        AND le.valuenum IS NOT NULL -- Ensure numeric value exists
        AND le.valueuom = 'ng/mL' -- Ensure consistent unit for categorization (FIXED: changed dli.unitname to le.valueuom)
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY le.subject_id, le.hadm_id ORDER BY le.charttime, le.labevent_id) = 1
),
CategorizedTroponin AS (
    SELECT
        valuenum,
        CASE
            WHEN valuenum < 0.014 THEN 'Normal (<0.014 ng/mL)'
            WHEN valuenum >= 0.014 AND valuenum < 0.052 THEN 'Borderline (0.014-0.051 ng/mL)'
            WHEN valuenum >= 0.052 THEN 'Elevated (>=0.052 ng/mL)'
            ELSE 'Unknown Category' -- Fallback, should not be reached with valuenum IS NOT NULL
        END AS troponin_category
    FROM
        InitialTroponinT
)
SELECT
    troponin_category,
    COUNT(1) AS count_admissions,
    -- Calculate percentage based on total number of initial Troponin T measurements in the cohort
    ROUND(CAST(COUNT(1) AS NUMERIC) * 100 / (SELECT COUNT(1) FROM CategorizedTroponin), 2) AS percentage,
    ROUND(AVG(valuenum), 3) AS mean_troponin,
    ROUND(APPROX_QUANTILES(valuenum, 100)[OFFSET(50)], 3) AS median_troponin, -- Median (50th percentile)
    ROUND(APPROX_QUANTILES(valuenum, 100)[OFFSET(25)], 3) AS q1_troponin,     -- 25th percentile
    ROUND(APPROX_QUANTILES(valuenum, 100)[OFFSET(75)], 3) AS q3_troponin      -- 75th percentile
FROM
    CategorizedTroponin
GROUP BY
    troponin_category
ORDER BY
    CASE troponin_category
        WHEN 'Normal (<0.014 ng/mL)' THEN 1
        WHEN 'Borderline (0.014-0.051 ng/mL)' THEN 2
        WHEN 'Elevated (>=0.052 ng/mL)' THEN 3
        ELSE 4
    END;