WITH creatinine_measurements AS (
    -- Select all serum creatinine measurements with valid numeric values
    SELECT
        le.subject_id,
        le.hadm_id,
        le.valuenum
    FROM
        `physionet-data.mimiciv_3_1_hosp.labevents` le
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
        ON le.itemid = dli.itemid
    WHERE
        dli.label = 'Creatinine' -- Identify Creatinine
        AND dli.fluid = 'Blood'   -- Ensure it's serum/blood creatinine
        AND le.valuenum IS NOT NULL -- Must have a numeric value
        AND le.valuenum > 0       -- Creatinine cannot be zero or negative
        AND le.valuenum <= 20     -- Filter out physiologically implausible high values (e.g., data entry errors)
),
nadir_creatinine_per_admission AS (
    -- Find the minimum (nadir) creatinine for each distinct hospital admission
    SELECT
        cm.subject_id,
        cm.hadm_id,
        MIN(cm.valuenum) AS nadir_creat
    FROM
        creatinine_measurements cm
    GROUP BY
        cm.subject_id,
        cm.hadm_id
),
male_nadir_creatinine_values AS (
    -- Get nadir creatinine values specifically for male patients
    SELECT
        nca.nadir_creat
    FROM
        nadir_creatinine_per_admission nca
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON nca.subject_id = p.subject_id
    WHERE
        p.gender = 'M' -- Filter for male patients only
)
-- Calculate the Interquartile Range (IQR) of nadir creatinine for males
SELECT
    PERCENTILE_CONT(nadir_creat, 0.25) OVER() AS q1_nadir_creat, -- 25th percentile
    PERCENTILE_CONT(nadir_creat, 0.75) OVER() AS q3_nadir_creat, -- 75th percentile
    (PERCENTILE_CONT(nadir_creat, 0.75) OVER() - PERCENTILE_CONT(nadir_creat, 0.25) OVER()) AS iqr_nadir_creat -- Interquartile Range
FROM
    male_nadir_creatinine_values
LIMIT 1; -- Limit to 1 row as the window function without PARTITION BY produces the same result for all rows;