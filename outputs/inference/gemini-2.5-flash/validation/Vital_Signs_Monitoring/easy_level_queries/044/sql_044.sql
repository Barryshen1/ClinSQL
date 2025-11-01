WITH TargetPatients AS (
    -- Step 1: Identify female patients aged 82-92
    SELECT
        p.subject_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 82 AND 92
),
MAP_Measurements AS (
    -- Step 2: Retrieve all Mean Arterial Pressure (MAP) measurements for the target patients
    SELECT
        icu.subject_id,
        icu.hadm_id, -- hospital admission ID
        ce.valuenum AS map_value
    FROM
        TargetPatients AS tp
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` AS icu
        ON tp.subject_id = icu.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
        ON icu.subject_id = ce.subject_id
        AND icu.hadm_id = ce.hadm_id
        AND icu.stay_id = ce.stay_id
    WHERE
        ce.itemid IN (
            220052, -- Arterial Blood Pressure mean
            220181, -- Non Invasive Blood Pressure mean
            224670  -- NBP Mean
        )
        AND ce.valuenum IS NOT NULL -- Ensure a numeric value exists
        AND ce.valuenum BETWEEN 20 AND 200 -- Physiologically plausible range for MAP
),
MaxMAP_PerHospitalStay AS (
    -- Step 3: Calculate the maximum MAP for each distinct hospital stay
    SELECT
        subject_id,
        hadm_id,
        MAX(map_value) AS max_map
    FROM
        MAP_Measurements
    GROUP BY
        subject_id,
        hadm_id
),
RankedMaxMAP AS (
    -- Step 4: Rank the maximum MAP values and count total rows for median calculation
    SELECT
        max_map,
        ROW_NUMBER() OVER (ORDER BY max_map) AS rn,
        COUNT(1) OVER () AS total_rows
    FROM
        MaxMAP_PerHospitalStay
)
-- Step 5: Calculate the median of these maximum MAP values
SELECT
    AVG(max_map) AS median_of_max_map_per_hospital_stay
FROM
    RankedMaxMAP
WHERE
    -- Select the middle row for odd counts, or the two middle rows for even counts.
    -- CEIL(total_rows / 2.0) gives the (N+1)/2 position for odd N, and N/2 position for even N.
    -- FLOOR(total_rows / 2.0) + 1 gives the (N+1)/2 position for odd N, and (N/2)+1 position for even N.
    -- Combining them correctly selects the necessary rows for calculating AVG for the median.
    rn = CEIL(total_rows / 2.0) OR rn = FLOOR(total_rows / 2.0) + 1;