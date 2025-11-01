WITH PatientECGTelemetryCounts AS (
    SELECT
        p.subject_id,
        COUNT(DISTINCT ce.itemid) AS distinct_procedure_count
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON p.subject_id = ce.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 51 AND 61
        AND ce.itemid IN (
            220046, -- Rhythms (commonly charted during telemetry monitoring)
            220047, -- Interpret ECG (an interpretation implies an ECG was performed)
            223945, -- ECG monitoring (explicitly indicates ECG monitoring)
            226500  -- EKG Leads (related to the setup of ECG/EKG equipment)
        )
    GROUP BY
        p.subject_id
)
SELECT
    -- Use APPROX_QUANTILES to estimate the 25th percentile.
    -- The second argument (100) specifies we want 100 quantiles (percentiles).
    -- [OFFSET(25)] then extracts the value for the 25th percentile from the resulting array of quantiles.
    APPROX_QUANTILES(distinct_procedure_count, 100)[OFFSET(25)] AS percentile_25_distinct_ecg_telemetry_procedures
FROM
    PatientECGTelemetryCounts;