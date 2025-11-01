WITH IHD_Admissions AS (
    -- Step 1: Identify all hospital admissions for the target patient cohort.
    -- Cohort: Males, 47-57 years old, admitted for Ischemic Heart Disease.
    SELECT DISTINCT
        adm.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        ON adm.hadm_id = dx.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddx
        ON dx.icd_code = ddx.icd_code AND dx.icd_version = ddx.icd_version
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 47 AND 57
        AND (
            LOWER(ddx.long_title) LIKE '%ischemic heart disease%'
            OR LOWER(ddx.long_title) LIKE '%myocardial infarction%'
        )
),

Ranked_Troponin AS (
    -- Step 2: For the identified admissions, find and rank all Troponin-T measurements by time.
    SELECT
        le.hadm_id,
        le.valuenum,
        -- Rank the troponin tests for each admission chronologically
        ROW_NUMBER() OVER(PARTITION BY le.hadm_id ORDER BY le.charttime ASC) as rn
    FROM
        `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    INNER JOIN
        IHD_Admissions AS iha
        ON le.hadm_id = iha.hadm_id
    WHERE
        -- itemid 51003 corresponds to 'Troponin T' in d_labitems
        le.itemid = 51003
        AND le.valuenum IS NOT NULL
        -- Ensure the unit is correct to match the threshold given in the question
        AND le.valueuom = 'ng/mL'
)

-- Step 3 & 4: Filter for the first measurement, apply the value threshold, and calculate statistics.
SELECT
    -- Median (50th percentile)
    APPROX_QUANTILES(t.valuenum, 100)[OFFSET(50)] AS median_troponin_t,
    -- Interquartile Range (IQR) calculated as 75th percentile - 25th percentile
    APPROX_QUANTILES(t.valuenum, 100)[OFFSET(75)] - APPROX_QUANTILES(t.valuenum, 100)[OFFSET(25)] AS iqr_troponin_t
FROM
    Ranked_Troponin AS t
WHERE
    -- Filter for only the first measurement in each admission
    t.rn = 1
    -- Filter for admissions where this first measurement exceeded the 99th percentile threshold
    AND t.valuenum > 0.014;