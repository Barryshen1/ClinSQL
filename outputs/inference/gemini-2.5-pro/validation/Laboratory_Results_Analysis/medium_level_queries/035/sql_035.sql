WITH first_troponin AS (
    -- This CTE identifies the first Troponin T measurement for each hospital admission.
    SELECT
        hadm_id,
        valuenum,
        ref_range_upper,
        -- Rank troponin results by time for each hospital stay
        ROW_NUMBER() OVER(PARTITION BY hadm_id ORDER BY charttime) as rn
    FROM
        `physionet-data.mimiciv_3_1_hosp.labevents`
    WHERE
        itemid = 51003 -- itemid for 'Troponin T'
)

SELECT
    -- Final aggregated statistics for the cohort
    COUNT(DISTINCT adm.hadm_id) AS number_of_patients,
    AVG(DATETIME_DIFF(adm.dischtime, adm.admittime, DAY)) AS avg_length_of_stay_days,
    AVG(CAST(adm.hospital_expire_flag AS FLOAT64)) * 100 AS in_hospital_mortality_percent
FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
JOIN
    first_troponin AS ft
    ON adm.hadm_id = ft.hadm_id
WHERE
    -- 1. Filter for male patients
    pat.gender = 'M'
    -- 2. Calculate and filter for age at admission
    AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 73 AND 83
    -- 3. Filter for the first troponin measurement only
    AND ft.rn = 1
    -- 4. Filter for elevated troponin levels
    AND ft.valuenum > ft.ref_range_upper
    -- 5. Ensure values used for comparison are not null
    AND ft.valuenum IS NOT NULL
    AND ft.ref_range_upper IS NOT NULL;