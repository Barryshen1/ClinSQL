WITH cap_admissions AS (
    -- First, find all hospital admissions where the primary diagnosis is a form of pneumonia
    -- typically considered community-acquired.
    SELECT
        hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        -- seq_num = 1 indicates the primary diagnosis for the admission
        seq_num = 1
        AND
        (
            -- ICD-9 codes for pneumonia (excluding pneumonia in diseases classified elsewhere)
            (icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('480', '481', '482', '483', '485', '486'))
            -- ICD-10 codes for pneumonia
            OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('J12', 'J13', 'J14', 'J15', 'J16', 'J17', 'J18'))
        )
)

-- Main query to calculate median LOS for the specified cohort
SELECT
    -- Use APPROX_QUANTILES to calculate the median (50th percentile)
    -- This is robust to outliers often found in LOS data.
    APPROX_QUANTILES(
        DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0, 2
    )[OFFSET(1)] AS median_hospital_los_days
FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
-- Join to get only admissions with a primary diagnosis of CAP
INNER JOIN cap_admissions AS cap
    ON adm.hadm_id = cap.hadm_id
-- Join to patient demographics to filter by gender and age
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
WHERE
    -- Filter for female patients
    pat.gender = 'F'
    -- Filter for non-elective admissions, as CAP is an acute condition
    AND adm.admission_type != 'ELECTIVE'
    -- Calculate age at admission and filter for the 83-93 age range
    AND (
        pat.anchor_age + DATETIME_DIFF(adm.admittime, DATETIME(pat.anchor_year, 1, 1, 0, 0, 0), YEAR)
    ) BETWEEN 83 AND 93;