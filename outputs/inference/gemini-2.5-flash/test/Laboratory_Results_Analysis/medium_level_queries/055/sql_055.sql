WITH TargetAdmissions AS (
    -- Step 1: Identify eligible admissions based on gender, age, and primary diagnosis
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
        ON adm.hadm_id = diag.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dicd
        ON diag.icd_code = dicd.icd_code AND diag.icd_version = dicd.icd_version
    WHERE
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 81 AND 91
        AND diag.seq_num = 1 -- Principal diagnosis for admission
        AND (
            LOWER(dicd.long_title) LIKE '%chest pain%'
            OR LOWER(dicd.long_title) LIKE '%myocardial infarction%'
        )
    GROUP BY -- Use GROUP BY to ensure unique hadm_id for admissions satisfying criteria
        adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime
),
FirstHsTnT AS (
    -- Step 2: Get the first high-sensitivity Troponin T measurement for each eligible admission
    -- Step 3: Categorize the hs-TnT levels based on common clinical cutoffs (ng/mL)
    SELECT
        ta.hadm_id,
        ta.subject_id,
        ta.admittime,
        ta.dischtime,
        CASE
            WHEN le.valuenum < 0.006 THEN 'Normal'
            WHEN le.valuenum >= 0.006 AND le.valuenum < 0.015 THEN 'Borderline'
            WHEN le.valuenum >= 0.015 THEN 'Myocardial Injury'
            ELSE 'Unavailable/Invalid' -- Handles cases where valuenum might be unexpected, though filtered below
        END AS hs_tnt_category,
        DATETIME_DIFF(ta.dischtime, ta.admittime, DAY) AS los_days
    FROM
        TargetAdmissions AS ta
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        ON ta.subject_id = le.subject_id AND ta.hadm_id = le.hadm_id
    WHERE
        le.itemid = 51003 -- Itemid for Troponin T
        AND le.valuenum IS NOT NULL -- Exclude rows with no numeric value
        AND le.valuenum >= 0 -- Exclude potential non-physiological negative values
    QUALIFY ROW_NUMBER() OVER (PARTITION BY ta.hadm_id ORDER BY le.charttime, le.labevent_id) = 1
)
-- Step 4: Aggregate results to get counts, percentages, and mean LOS
SELECT
    fht.hs_tnt_category,
    COUNT(fht.hadm_id) AS patient_count, -- COUNT(hadm_id) is sufficient as FirstHsTnT already provides unique hadm_id per row
    ROUND(COUNT(fht.hadm_id) * 100.0 / SUM(COUNT(fht.hadm_id)) OVER(), 2) AS percentage,
    ROUND(AVG(fht.los_days), 2) AS mean_los_days
FROM
    FirstHsTnT AS fht
WHERE
    fht.hs_tnt_category != 'Unavailable/Invalid' -- Exclude any cases where categorization might have failed unexpectedly
GROUP BY
    fht.hs_tnt_category
ORDER BY
    CASE
        WHEN fht.hs_tnt_category = 'Normal' THEN 1
        WHEN fht.hs_tnt_category = 'Borderline' THEN 2
        WHEN fht.hs_tnt_category = 'Myocardial Injury' THEN 3
        ELSE 4 -- Catches 'Unavailable/Invalid' making sure it's last if not filtered
    END;