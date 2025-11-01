WITH CohortStays AS (
    -- Step 1: Identify the target patient cohort based on age and gender
    SELECT
        icustays.subject_id,
        icustays.hadm_id,
        icustays.stay_id,
        icustays.intime,
        icustays.outtime
    FROM
        `physionet-data.mimiciv_3_1_icu.icustays` icustays
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` patients
        ON icustays.subject_id = patients.subject_id
    WHERE
        patients.gender = 'F'
        AND patients.anchor_age BETWEEN 48 AND 58
),
AvgHR_First48h AS (
    -- Step 2: Calculate the average Heart Rate (HR) for each ICU stay within the first 48 hours
    SELECT
        cs.stay_id,
        AVG(ce.valuenum) AS avg_hr_48h
    FROM
        CohortStays cs
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON cs.subject_id = ce.subject_id
        AND cs.stay_id = ce.stay_id
    WHERE
        ce.itemid = 220045 -- Itemid for Heart Rate in MIMIC-IV ICU d_items
        AND ce.charttime BETWEEN cs.intime AND DATETIME_ADD(cs.intime, INTERVAL 48 HOUR)
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum > 0
    GROUP BY
        cs.stay_id
),
AKI_AdmissionFlag AS (
    -- Step 3: Determine if Acute Kidney Injury (AKI) diagnosis exists for each hospital admission
    SELECT
        cs.hadm_id,
        MAX(CASE WHEN diagnoses_icd.icd_code LIKE 'N17%' THEN 1 ELSE 0 END) AS has_aki
    FROM
        CohortStays cs
    LEFT JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diagnoses_icd
        ON cs.hadm_id = diagnoses_icd.hadm_id
    GROUP BY
        cs.hadm_id
),
CombinedStayData AS (
    -- Step 4: Combine HR data and AKI flag for each ICU stay
    SELECT
        cs.subject_id,
        cs.hadm_id,
        cs.stay_id,
        ah.avg_hr_48h,
        COALESCE(af.has_aki, 0) AS has_aki_diagnosis -- Default to 0 if no AKI diagnosis was found for the admission
    FROM
        CohortStays cs
    LEFT JOIN
        AvgHR_First48h ah
        ON cs.stay_id = ah.stay_id
    LEFT JOIN
        AKI_AdmissionFlag af
        ON cs.hadm_id = af.hadm_id
)
SELECT
    cd.hr_category,
    COUNT(cd.stay_id) AS num_stays,
    ROUND(COUNT(cd.stay_id) * 100.0 / SUM(COUNT(cd.stay_id)) OVER (), 2) AS percent_hr_distribution,
    SUM(CASE WHEN cd.has_aki_diagnosis = 1 THEN 1 ELSE 0 END) AS num_aki_stays,
    ROUND(SUM(CASE WHEN cd.has_aki_diagnosis = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(cd.stay_id), 2) AS aki_rate_percent_by_hr_category
FROM
    (
        -- Categorize HR data for each stay
        SELECT
            stay_id,
            CASE
                WHEN avg_hr_48h IS NULL THEN 'No HR Data' -- Handle stays with no HR data in the first 48h
                WHEN avg_hr_48h < 60 THEN '<60 bpm'
                WHEN avg_hr_48h BETWEEN 60 AND 99 THEN '60-99 bpm'
                WHEN avg_hr_48h BETWEEN 100 AND 119 THEN '100-119 bpm'
                WHEN avg_hr_48h >= 120 THEN '>=120 bpm'
                ELSE 'Unknown' -- Should not be reached if avg_hr_48h is not null and positive
            END AS hr_category,
            has_aki_diagnosis
        FROM
            CombinedStayData
    ) AS cd
WHERE
    cd.hr_category != 'No HR Data' -- Exclude stays without HR data from the HR distribution report
GROUP BY
    cd.hr_category
ORDER BY
    CASE cd.hr_category
        WHEN '<60 bpm' THEN 1
        WHEN '60-99 bpm' THEN 2
        WHEN '100-119 bpm' THEN 3
        WHEN '>=120 bpm' THEN 4
        ELSE 5 -- For 'Unknown' if it ever appears
    END;