WITH PatientICUStays AS (
    -- Select subject_ids and ICU stays for 63-year-old male patients
    SELECT
        p.subject_id,
        p.gender,
        p.anchor_age,
        ics.hadm_id,
        ics.stay_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` ics
        ON p.subject_id = ics.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age = 63 -- Filter for 63-year-old males based on anchor_age
),
ABG_pH_Measurements AS (
    -- Retrieve arterial pH measurements for the selected ICU stays
    SELECT
        pist.subject_id,
        pist.hadm_id,
        pist.stay_id,
        ce.valuenum AS ph_value
    FROM
        PatientICUStays pist
    JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON pist.stay_id = ce.stay_id
    WHERE
        ce.itemid = 220274 -- itemid for 'pH' (Arterial) found in d_items
        AND ce.valuenum IS NOT NULL
        AND ce.valuenum >= 6.5 -- Filter for physiologically plausible pH values
        AND ce.valuenum <= 8.0
),
PeakABG_pH_PerStay AS (
    -- Calculate the peak arterial pH for each ICU stay
    SELECT
        subject_id,
        hadm_id,
        stay_id,
        MAX(ph_value) AS peak_ph
    FROM
        ABG_pH_Measurements
    GROUP BY
        subject_id,
        hadm_id,
        stay_id
)
-- Calculate the Interquartile Range (IQR) of these peak pH values
SELECT
    PERCENTILE_CONT(peak_ph, 0.25) OVER() AS Q1,
    PERCENTILE_CONT(peak_ph, 0.75) OVER() AS Q3,
    (PERCENTILE_CONT(peak_ph, 0.75) OVER() - PERCENTILE_CONT(peak_ph, 0.25) OVER()) AS IQR
FROM
    PeakABG_pH_PerStay
QUALIFY ROW_NUMBER() OVER() = 1 -- Ensure only one row is returned with the overall percentiles;