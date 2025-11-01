WITH
    -- CTE 1: Target Patient Population (Female, 90-100 years old at admission, with ICU stays)
    target_patients_icu AS (
        SELECT
            p.subject_id,
            adm.hadm_id,
            icu.stay_id,
            icu.intime,
            icu.outtime
        FROM
            `physionet-data.mimiciv_3_1_hosp.patients` AS p
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
            ON p.subject_id = adm.subject_id
        INNER JOIN
            `physionet-data.mimiciv_3_1_icu.icustays` AS icu
            ON adm.hadm_id = icu.hadm_id AND p.subject_id = icu.subject_id
        WHERE
            p.gender = 'F'
            AND p.anchor_age BETWEEN 90 AND 100
    ),
    -- CTE 2: First 24-hour Average SpO2 per ICU Stay
    first_24h_spo2 AS (
        SELECT
            t.subject_id,
            t.hadm_id,
            t.stay_id,
            AVG(ce.valuenum) AS avg_spo2_24h
        FROM
            target_patients_icu AS t
        INNER JOIN
            `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
            ON t.stay_id = ce.stay_id
        WHERE
            -- ItemIDs for SpO2 (Pulse Oximetry or SaO2 saturation)
            ce.itemid IN (220277, 223769)
            AND ce.valuenum IS NOT NULL
            AND ce.valuenum BETWEEN 0 AND 100 -- Filter for realistic SpO2 values
            AND ce.charttime BETWEEN t.intime AND TIMESTAMP_ADD(t.intime, INTERVAL 24 HOUR)
        GROUP BY
            t.subject_id,
            t.hadm_id,
            t.stay_id
        HAVING
            COUNT(ce.valuenum) >= 5 -- Require at least 5 measurements for a meaningful average
    ),
    -- CTE 3: AKI status per Hospital Admission
    aki_status AS (
        SELECT
            hadm_id,
            MAX(
                CASE
                    WHEN (
                        (d.icd_version = 10 AND d.icd_code LIKE 'N17.%') -- ICD-10 codes for AKI (N17.0-N17.9)
                        OR (d.icd_version = 9 AND d.icd_code LIKE '584.%')  -- ICD-9 codes for AKI (584.5-584.9)
                    ) THEN 1
                    ELSE 0
                END
            ) AS has_aki
        FROM
            `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
        GROUP BY
            hadm_id
    ),
    -- CTE 4: Combine SpO2 averages and AKI status per ICU stay, and categorize SpO2
    categorized_stays AS (
        SELECT
            t.subject_id,
            t.hadm_id,
            t.stay_id,
            s.avg_spo2_24h,
            CASE
                WHEN s.avg_spo2_24h < 90 THEN '<90'
                WHEN s.avg_spo2_24h BETWEEN 90 AND 92 THEN '90-92'
                WHEN s.avg_spo2_24h BETWEEN 93 AND 95 THEN '93-95'
                WHEN s.avg_spo2_24h > 95 THEN '>95'
                ELSE NULL -- Should not happen with valuenum BETWEEN 0 AND 100 filter
            END AS spo2_category,
            COALESCE(a.has_aki, 0) AS has_aki -- Default to 0 if no AKI diagnosis found for the admission
        FROM
            target_patients_icu AS t
        INNER JOIN -- Use INNER JOIN to only include stays where a 24h SpO2 average was calculated
            first_24h_spo2 AS s
            ON t.stay_id = s.stay_id
        LEFT JOIN -- Use LEFT JOIN to include all relevant ICU stays, regardless of whether they have an AKI diagnosis
            aki_status AS a
            ON t.hadm_id = a.hadm_id
    )
-- Final aggregation to calculate N, mean, median, IQR, and AKI rate by SpO2 category
SELECT
    cs.spo2_category,
    COUNT(DISTINCT cs.stay_id) AS N_ICU_Stays, -- N, representing the number of ICU stays
    ROUND(AVG(cs.avg_spo2_24h), 2) AS mean_spo2_24h,
    -- Replaced PERCENTILE_CONT with PERCENTILE_APPROX
    ROUND(PERCENTILE_APPROX(cs.avg_spo2_24h, 0.5) , 2) AS median_spo2_24h,
    ROUND(PERCENTILE_APPROX(cs.avg_spo2_24h, 0.75) - PERCENTILE_APPROX(cs.avg_spo2_24h, 0.25) , 2) AS iqr_spo2_24h,
    ROUND(AVG(cs.has_aki) * 100, 2) AS aki_rate_percent -- AKI rate as a percentage
FROM
    categorized_stays AS cs
WHERE
    cs.spo2_category IS NOT NULL -- Exclude any stays where SpO2 could not be categorized
GROUP BY
    cs.spo2_category
ORDER BY
    -- Ensure the categories are ordered logically in the final output
    CASE cs.spo2_category
        WHEN '<90' THEN 1
        WHEN '90-92' THEN 2
        WHEN '93-95' THEN 3
        WHEN '>95' THEN 4
        ELSE 5 -- Fallback for any unexpected categories (though none expected with filtering)
    END;