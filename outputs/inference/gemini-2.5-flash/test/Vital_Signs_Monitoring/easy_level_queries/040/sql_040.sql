WITH PatientICUStays AS (
    SELECT
        p.subject_id,
        icustays.stay_id,
        -- Calculate age at ICU admission
        (p.anchor_age + (EXTRACT(YEAR FROM icustays.intime) - p.anchor_year)) AS age_at_admission
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` AS icustays
        ON p.subject_id = icustays.subject_id
    WHERE
        p.gender = 'M' -- Filter for male patients
        AND (p.anchor_age + (EXTRACT(YEAR FROM icustays.intime) - p.anchor_year)) BETWEEN 55 AND 65 -- Filter for age 55-65
),
FirstMAPMeasurements AS (
    SELECT
        ce.stay_id,
        ce.valuenum AS first_map_value
    FROM
        `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    WHERE
        ce.itemid IN (
            220052, -- Arterial Blood Pressure mean
            220181  -- Non Invasive Blood Pressure mean
        )
        AND ce.valuenum IS NOT NULL -- Ensure value is not null
        AND ce.valuenum > 0     -- Filter out non-physiological values
        AND ce.valuenum < 300   -- Filter out non-physiological values (e.g., >300 mmHg is highly unlikely for MAP)
    QUALIFY ROW_NUMBER() OVER (PARTITION BY ce.stay_id ORDER BY ce.charttime, ce.storetime, ce.itemid) = 1
    -- Use QUALIFY to get the first MAP measurement for each ICU stay
)
SELECT
    STDDEV(fm.first_map_value) AS sd_of_first_map_on_icu_admission
FROM
    PatientICUStays AS pis
INNER JOIN
    FirstMAPMeasurements AS fm
    ON pis.stay_id = fm.stay_id;