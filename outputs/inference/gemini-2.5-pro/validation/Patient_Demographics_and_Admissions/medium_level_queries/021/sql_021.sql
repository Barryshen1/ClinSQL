WITH surgical_admissions AS (
    -- This CTE identifies hospital admissions that included a stay on any surgical service.
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.services`
    WHERE curr_service IN (
        'SURG',  -- General Surgery
        'CSURG', -- Cardiac Surgery
        'NSURG', -- Neurosurgery
        'TSURG', -- Thoracic Surgery
        'VSURG', -- Vascular Surgery
        'ORTHO', -- Orthopedic Surgery
        'TRAUM', -- Trauma
        'GU',    -- Genitourinary
        'ENT',   -- Ear, Nose, Throat
        'PSURG', -- Plastic Surgery
        'DENT'   -- Dental
    )
),
cohort_data AS (
    -- This CTE selects the cohort of patients, calculates their LOS, and categorizes their discharge outcome.
    SELECT
        -- Calculate hospital length of stay in fractional days for precision.
        DATETIME_DIFF(adm.dischtime, adm.admittime, SECOND) / (24.0 * 60 * 60) AS los_days,

        -- Categorize discharge outcome, prioritizing mortality.
        CASE
            WHEN adm.hospital_expire_flag = 1 THEN 'In-hospital Mortality'
            WHEN adm.discharge_location LIKE 'HOME%' THEN 'Discharged Home'
            ELSE 'Discharged to Facility'
        END AS outcome_category
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN
        surgical_admissions AS surg
        ON adm.hadm_id = surg.hadm_id
    WHERE
        -- Filter for male patients aged 67-77.
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 67 AND 77
        -- Exclude admissions where LOS cannot be calculated.
        AND adm.dischtime IS NOT NULL AND adm.admittime IS NOT NULL
)
-- Final aggregation and formatting of the results.
SELECT
    outcome_category,
    FORMAT('%.1f ± %.1f', AVG(los_days), STDDEV(los_days)) AS mean_sd_los_days,
    FORMAT('%.1f', AVG(CASE WHEN los_days <= 7 THEN 1.0 ELSE 0.0 END) * 100) AS percent_los_le_7_days
FROM
    cohort_data
GROUP BY
    outcome_category
ORDER BY
    -- Order for consistent and readable output.
    outcome_category;