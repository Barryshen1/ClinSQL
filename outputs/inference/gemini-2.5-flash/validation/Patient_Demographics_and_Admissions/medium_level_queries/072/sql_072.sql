WITH TargetAdmissions AS (
    -- Select relevant admissions and patient demographics
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag,
        ad.discharge_location,
        p.gender,
        p.anchor_age,
        -- Calculate Length of Stay in fractional days
        DATETIME_DIFF(ad.dischtime, ad.admittime, HOUR) / 24.0 AS los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON ad.subject_id = p.subject_id
    WHERE
        p.gender = 'M' -- Male patients
        AND p.anchor_age BETWEEN 74 AND 84 -- Aged 74-84
        AND ad.dischtime > ad.admittime -- Ensure valid discharge time for LOS calculation
),
MedicineAdmissions AS (
    -- Identify admissions where the *first* service was a medicine service
    -- This assumes 'medicine inpatients' refers to the primary service type upon admission.
    SELECT
        s.hadm_id
    FROM (
        SELECT
            s_inner.hadm_id,
            s_inner.curr_service,
            ROW_NUMBER() OVER (PARTITION BY s_inner.hadm_id ORDER BY s_inner.transfertime) AS rn
        FROM
            `physionet-data.mimiciv_3_1_hosp.services` AS s_inner
    ) AS s
    WHERE
        s.rn = 1 -- Only consider the first service for the admission
        AND s.curr_service IN ('MED', 'CMED', 'GENMED', 'TRAUMED', 'GPM', 'OBSMED') -- Common medicine service types in MIMIC-IV
)
SELECT
    CASE
        WHEN ta.hospital_expire_flag = 1 THEN 'In-hospital Death'
        WHEN ta.discharge_location IN ('Hospice', 'Hospice - Home', 'Hospice - Medical Facility') THEN 'Hospice'
        WHEN ta.discharge_location IN ('Home', 'Home Health Care') THEN 'Discharge Home'
        -- Any other discharge_location not explicitly asked for is implicitly excluded by the WHERE clause below
        ELSE 'Other_Discharge_Type_Excluded' -- Placeholder for outcomes to be filtered out
    END AS discharge_outcome_category,
    COUNT(DISTINCT ta.hadm_id) AS num_admissions,
    ROUND(AVG(ta.los_days), 2) AS mean_los_days,
    APPROX_QUANTILES(ta.los_days, 100)[OFFSET(50)] AS median_los_days,
    ROUND(COUNTIF(ta.los_days <= 5) * 100.0 / COUNT(ta.hadm_id), 2) AS proportion_los_le_5_percent
FROM
    TargetAdmissions AS ta
INNER JOIN
    MedicineAdmissions AS ma
    ON ta.hadm_id = ma.hadm_id
WHERE
    -- Filter to include only the specified discharge outcomes (home, hospice, in-hospital death)
    (ta.hospital_expire_flag = 1
    OR ta.discharge_location IN ('Hospice', 'Hospice - Home', 'Hospice - Medical Facility')
    OR ta.discharge_location IN ('Home', 'Home Health Care'))
GROUP BY
    discharge_outcome_category
ORDER BY
    discharge_outcome_category;