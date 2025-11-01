WITH PatientPopulation AS (
    SELECT
        p.subject_id,
        ics.stay_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` ics
        ON p.subject_id = ics.subject_id
    WHERE
        p.gender = 'M' -- Filter for male patients
        AND p.anchor_age BETWEEN 77 AND 87 -- Filter for age range 77-87
),
FirstGCS AS (
    SELECT
        pp.stay_id,
        ce.valuenum AS gcs_total,
        ROW_NUMBER() OVER (PARTITION BY pp.stay_id ORDER BY ce.charttime ASC) AS rn
    FROM
        PatientPopulation pp
    JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON pp.subject_id = ce.subject_id
        AND pp.stay_id = ce.stay_id
    WHERE
        ce.itemid = 223900 -- itemid for GCS Total
        AND ce.valuenum IS NOT NULL -- Ensure a numeric value exists
)
SELECT
    AVG(fg.gcs_total) AS average_first_gcs_total
FROM
    FirstGCS fg
WHERE
    fg.rn = 1; -- Select only the first recorded GCS total for each ICU stay;