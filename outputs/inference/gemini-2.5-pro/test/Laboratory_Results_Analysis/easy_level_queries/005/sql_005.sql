WITH first_sodium AS (
    SELECT
        le.valuenum,
        -- Rank sodium measurements by time for each hospital admission
        ROW_NUMBER() OVER(PARTITION BY le.hadm_id ORDER BY le.charttime) as rn
    FROM
        `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    INNER JOIN (
        -- Identify unique hospital admissions for male patients with an ICU stay
        SELECT DISTINCT icu.hadm_id
        FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
            ON icu.subject_id = p.subject_id
        WHERE p.gender = 'M'
    ) AS male_icu_admissions
        ON le.hadm_id = male_icu_admissions.hadm_id
    WHERE
        le.itemid = 50983 -- 50983 is the itemid for Sodium, Serum
        AND le.valuenum IS NOT NULL
)
SELECT
    -- Calculate p75 - p25 to get the IQR
    APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] - APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS sodium_iqr
FROM first_sodium
WHERE
    rn = 1 -- Filter for only the first measurement per admission;