WITH SepsisFemale76yoAdmissions AS (
    SELECT DISTINCT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id
    WHERE
        pat.anchor_age = 76 -- Filter for 76-year-old patients
        AND pat.gender = 'F' -- Filter for female patients
        AND (
            -- Sepsis ICD-10 codes (A40.x, A41.x)
            (diag.icd_version = 10 AND (diag.icd_code LIKE 'A40%' OR diag.icd_code LIKE 'A41%'))
            OR
            -- Sepsis ICD-9 codes (038.x, 995.91, 995.92)
            (diag.icd_version = 9 AND (diag.icd_code LIKE '038%' OR diag.icd_code = '99591' OR diag.icd_code = '99592'))
        )
),
-- For each identified admission, extract platelet counts within the first 24 hours
-- and calculate the average for that admission.
CombinedPlateletAverages AS (
    SELECT
        sfa.subject_id,
        sfa.hadm_id,
        AVG(le.valuenum) AS avg_platelet_24hr
    FROM
        SepsisFemale76yoAdmissions sfa
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON sfa.subject_id = le.subject_id
        AND sfa.hadm_id = le.hadm_id
    WHERE
        le.itemid = 51265 -- itemid for 'Platelet Count'
        AND le.valuenum IS NOT NULL -- Ensure a numeric value exists
        AND le.valuenum > 0 -- Ensure platelet count is positive and sensible
        AND le.charttime >= sfa.admittime
        AND le.charttime <= TIMESTAMP_ADD(sfa.admittime, INTERVAL 24 HOUR) -- Within first 24 hours of admission
    GROUP BY
        sfa.subject_id,
        sfa.hadm_id
)
-- Calculate the median of these 24-hour average platelet counts.
SELECT
    APPROX_QUANTILES(avg_platelet_24hr, 2)[OFFSET(1)] AS median_avg_platelet_count_24hr
FROM
    CombinedPlateletAverages
WHERE
    avg_platelet_24hr IS NOT NULL; -- Exclude admissions where no platelet count was found in the first 24 hours;