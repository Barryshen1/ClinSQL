WITH
-- Step 1: Identify all ICU stays for female patients aged 90-100 at admission.
cohort_stays AS (
    SELECT
        p.subject_id,
        i.hadm_id,
        i.stay_id,
        i.intime,
        -- Calculate age at ICU admission. This is a common and reliable approximation.
        (EXTRACT(YEAR FROM i.intime) - p.anchor_year) + p.anchor_age AS age_at_icustay
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` AS i
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
            ON i.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        AND (EXTRACT(YEAR FROM i.intime) - p.anchor_year) + p.anchor_age >= 90
        AND (EXTRACT(YEAR FROM i.intime) - p.anchor_year) + p.anchor_age <= 100
),

-- Step 2: Calculate the average SpO2 in the first 24 hours for each stay in the cohort.
first_24h_spo2 AS (
    SELECT
        c.stay_id,
        AVG(ce.valuenum) AS avg_spo2
    FROM
        cohort_stays AS c
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
            ON c.stay_id = ce.stay_id
    WHERE
        ce.itemid IN (
            220277, -- O2 saturation pulseoxymetry (Metavision)
            646     -- SpO2 (CareVue)
        )
        AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum > 0 AND ce.valuenum <= 100 -- Filter for plausible SpO2 values
    GROUP BY
        c.stay_id
),

-- Step 3: Identify hospital admissions with a diagnosis of Acute Kidney Injury (AKI).
aki_diagnoses AS (
    SELECT DISTINCT
        hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        -- ICD-9 codes for AKI (note: no decimal points in the table)
        (icd_version = 9 AND icd_code IN ('5845', '5846', '5847', '5848', '5849'))
        -- ICD-10 codes for AKI (N17 family)
        OR (icd_version = 10 AND STARTS_WITH(icd_code, 'N17'))
),

-- Step 4: Combine stay data, SpO2, and AKI information, and categorize SpO2.
final_data AS (
    SELECT
        cs.stay_id,
        s.avg_spo2,
        CASE
            WHEN akid.hadm_id IS NOT NULL THEN 1
            ELSE 0
        END AS aki_flag,
        -- Categorize the average SpO2 into the requested groups
        CASE
            WHEN s.avg_spo2 < 90 THEN '<90'
            WHEN s.avg_spo2 >= 90 AND s.avg_spo2 <= 92 THEN '90-92'
            WHEN s.avg_spo2 > 92 AND s.avg_spo2 <= 95 THEN '93-95'
            WHEN s.avg_spo2 > 95 THEN '>95'
            ELSE NULL
        END AS spo2_group
    FROM
        cohort_stays AS cs
    INNER JOIN -- Use INNER JOIN to only include stays from the cohort that have SpO2 data
        first_24h_spo2 AS s
            ON cs.stay_id = s.stay_id
    LEFT JOIN -- Use LEFT JOIN as the absence of an AKI diagnosis is valid (aki_flag = 0)
        aki_diagnoses AS akid
            ON cs.hadm_id = akid.hadm_id
)

-- Step 5: Group by the SpO2 category and calculate the requested statistics.
SELECT
    spo2_group,
    COUNT(stay_id) AS N_stays,
    AVG(avg_spo2) AS mean_avg_spo2,
    APPROX_QUANTILES(avg_spo2, 100)[OFFSET(50)] AS median_avg_spo2,
    (
        APPROX_QUANTILES(avg_spo2, 100)[OFFSET(75)] - APPROX_QUANTILES(avg_spo2, 100)[OFFSET(25)]
    ) AS iqr_avg_spo2,
    AVG(aki_flag) AS aki_rate
FROM
    final_data
WHERE
    spo2_group IS NOT NULL -- Exclude any stays that didn't fall into a category
GROUP BY
    spo2_group
ORDER BY
    -- Custom sort order for the groups to ensure a logical presentation
    CASE
        WHEN spo2_group = '<90' THEN 1
        WHEN spo2_group = '90-92' THEN 2
        WHEN spo2_group = '93-95' THEN 3
        WHEN spo2_group = '>95' THEN 4
    END;