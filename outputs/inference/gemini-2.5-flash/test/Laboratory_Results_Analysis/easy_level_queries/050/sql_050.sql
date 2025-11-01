WITH FilteredPlatelets AS (
    SELECT
        le.valuenum,
        ROW_NUMBER() OVER (PARTITION BY ad.hadm_id ORDER BY le.charttime, le.labevent_id) AS rn
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON ad.subject_id = p.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
        ON ad.hadm_id = di.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        ON ad.subject_id = le.subject_id
        AND ad.hadm_id = le.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
        ON le.itemid = dli.itemid
    WHERE
        p.gender = 'M'
        AND p.anchor_age = 44 -- Filters for male patients who were 44 years old at their anchor year
        AND (
            -- Sepsis ICD-9 codes
            (di.icd_version = 9 AND di.icd_code IN ('99591', '99592'))
            OR
            -- Sepsis ICD-10 codes
            (di.icd_version = 10 AND (di.icd_code LIKE 'A40%' OR di.icd_code LIKE 'A41%' OR di.icd_code LIKE 'R65.2%'))
        )
        AND dli.label = 'Platelet Count' -- Filter for Platelet Count lab item
        AND le.valuenum IS NOT NULL -- Ensure the lab value is numeric and not null
        -- Only consider lab results taken within the first 24 hours of admission
        AND le.charttime BETWEEN ad.admittime AND DATETIME_ADD(ad.admittime, INTERVAL 24 HOUR)
)
SELECT
    STDDEV(valuenum) AS admission_platelet_stddev
FROM
    FilteredPlatelets
WHERE
    rn = 1;