WITH MalePneumoniaAdmissions AS (
    SELECT DISTINCT
        a.subject_id,
        a.hadm_id,
        a.dischtime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON a.subject_id = p.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
        ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
    WHERE
        p.gender = 'M'
        -- Filter for common ICD codes indicating pneumonia
        AND (
            (di.icd_version = 9 AND di.icd_code LIKE '48[0-6]%') -- ICD-9 codes 480-486 for pneumonia
            OR
            (di.icd_version = 10 AND di.icd_code LIKE 'J1[0-8]%') -- ICD-10 codes J10-J18 for pneumonia
        )
),
DischargeGlucoseValues AS (
    SELECT
        le.valuenum AS serum_glucose_discharge_value
    FROM
        MalePneumoniaAdmissions AS mpa
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        ON mpa.subject_id = le.subject_id AND mpa.hadm_id = le.hadm_id
    WHERE
        le.itemid = 50931 -- Specific itemid for 'Glucose, Serum' (from d_labitems)
        AND le.valuenum IS NOT NULL -- Ensure a numeric value exists
        AND le.charttime <= mpa.dischtime -- Measurement must be on or before discharge
    QUALIFY ROW_NUMBER() OVER (PARTITION BY mpa.subject_id, mpa.hadm_id ORDER BY le.charttime DESC, le.labevent_id DESC) = 1
    -- In case of ties in charttime, labevent_id provides a consistent tie-breaking mechanism.
)
SELECT
    -- Corrected PERCENTILE_CONT syntax for BigQuery
    PERCENTILE_CONT(serum_glucose_discharge_value, 0.75) OVER () AS 75th_percentile_serum_glucose_at_discharge
FROM
    DischargeGlucoseValues
LIMIT 1; -- Limit to 1 because PERCENTILE_CONT OVER () will return the same value for all rows;