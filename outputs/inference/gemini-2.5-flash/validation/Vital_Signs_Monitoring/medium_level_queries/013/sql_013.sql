WITH TargetPatients AS (
    -- Step 1: Identify male ICU patients aged 51-61
    SELECT
        p.subject_id,
        adm.hadm_id,
        ie.stay_id,
        ie.intime
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON p.subject_id = adm.subject_id
    JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` ie
        ON adm.hadm_id = ie.hadm_id AND p.subject_id = ie.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 51 AND 61
),
RawSpO2 AS (
    -- Step 2a: Extract SpO2 measurements within the first 48 hours of ICU stay
    SELECT
        tp.subject_id,
        tp.hadm_id,
        tp.stay_id,
        ce.valuenum
    FROM
        TargetPatients tp
    JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON tp.stay_id = ce.stay_id
    JOIN
        `physionet-data.mimiciv_3_1_icu.d_items` di
        ON ce.itemid = di.itemid
    WHERE
        -- SpO2 measurements within the first 48 hours of the ICU stay
        ce.charttime BETWEEN tp.intime AND DATETIME_ADD(tp.intime, INTERVAL 48 HOUR)
        -- Common itemids for O2 saturation pulseoxymetry
        AND ce.itemid IN (220277, 678, 834)
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum BETWEEN 0 AND 100 -- Filter for realistic SpO2 values
),
AvgSpO2PerStay AS (
    -- Step 2b: Calculate per-stay average SpO2 for the first 48 hours
    SELECT
        subject_id,
        hadm_id,
        stay_id,
        AVG(valuenum) AS avg_spo2_48hr
    FROM
        RawSpO2
    GROUP BY
        subject_id, hadm_id, stay_id
    HAVING
        COUNT(valuenum) >= 1 -- Ensure at least one valid SpO2 measurement
),
SpO2Category AS (
    -- Step 3: Categorize average SpO2 levels
    SELECT
        subject_id,
        hadm_id,
        stay_id,
        avg_spo2_48hr,
        CASE
            WHEN avg_spo2_48hr < 90 THEN '<90'
            WHEN avg_spo2_48hr >= 90 AND avg_spo2_48hr <= 92 THEN '90-92'
            WHEN avg_spo2_48hr >= 93 AND avg_spo2_48hr <= 95 THEN '93-95'
            WHEN avg_spo2_48hr > 95 THEN '>95'
            ELSE 'Unknown'
        END AS spo2_category_48hr
    FROM
        AvgSpO2PerStay
),
AKI_Status AS (
    -- Step 4: Determine AKI status for each relevant admission
    SELECT DISTINCT
        tp.subject_id,
        tp.hadm_id,
        tp.stay_id,
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
                WHERE
                    di.hadm_id = tp.hadm_id
                    AND di.icd_version = 10
                    AND di.icd_code LIKE 'N17.%' -- ICD-10 codes for Acute kidney failure
            ) THEN TRUE ELSE FALSE
        END AS has_aki
    FROM
        TargetPatients tp
)
-- Step 5: Combine SpO2 categories with AKI status and aggregate results
SELECT
    s.spo2_category_48hr,
    COUNT(DISTINCT s.stay_id) AS total_icu_stays_in_category, -- 'Patient counts' interpreted as count of ICU stays
    COUNT(DISTINCT CASE WHEN a.has_aki THEN s.stay_id END) AS icu_stays_with_aki, -- Number of ICU stays where the associated admission had AKI
    ROUND(
        CAST(COUNT(DISTINCT CASE WHEN a.has_aki THEN s.stay_id END) AS FLOAT64) * 100
        / COUNT(DISTINCT s.stay_id)
    , 2) AS aki_rate_percent
FROM
    SpO2Category s
LEFT JOIN
    AKI_Status a
    ON s.stay_id = a.stay_id
    AND s.subject_id = a.subject_id
    AND s.hadm_id = a.hadm_id
GROUP BY
    s.spo2_category_48hr
HAVING
    s.spo2_category_48hr != 'Unknown' -- Exclude stays where SpO2 couldn't be categorized
ORDER BY
    CASE s.spo2_category_48hr
        WHEN '<90' THEN 1
        WHEN '90-92' THEN 2
        WHEN '93-95' THEN 3
        WHEN '>95' THEN 4
        ELSE 5 -- For 'Unknown' if it ever appears after exclusion
    END;