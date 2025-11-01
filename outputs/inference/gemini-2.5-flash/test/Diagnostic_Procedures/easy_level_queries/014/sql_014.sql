WITH PatientAdmissions AS (
    SELECT
        p.subject_id,
        adm.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
    JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        ON p.subject_id = adm.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 73 AND 83
),
DeviceProcedures AS (
    SELECT DISTINCT -- Use DISTINCT here to ensure each hadm_id/device_type pair is unique
        pr.hadm_id,
        dp.long_title AS device_type
    FROM
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pr
    JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS dp
        ON pr.icd_code = dp.icd_code AND pr.icd_version = dp.icd_version
    WHERE
        LOWER(dp.long_title) LIKE '%heart assist%'
        OR LOWER(dp.long_title) LIKE '%ventricular assist%'
        OR LOWER(dp.long_title) LIKE '%extracorporeal membrane oxygenation%'
        OR LOWER(dp.long_title) LIKE '%ecmo system%'
        OR LOWER(dp.long_title) LIKE '%intra-aortic balloon pump%'
        OR LOWER(dp.long_title) LIKE '%cardiac pacemaker%'
        OR LOWER(dp.long_title) LIKE '%cardioverter-defibrillator%'
        OR LOWER(dp.long_title) LIKE '%circulatory support device%'
        OR LOWER(dp.long_title) LIKE '%artificial heart%'
),
HadmsWithDeviceCounts AS (
    SELECT
        pa.hadm_id,
        -- COUNT(dp.device_type) correctly counts non-NULL device types.
        -- If no devices for an admission, dp.device_type is NULL, and COUNT(NULL) is 0.
        COUNT(dp.device_type) AS num_distinct_devices
    FROM
        PatientAdmissions AS pa
    LEFT JOIN
        DeviceProcedures AS dp
        ON pa.hadm_id = dp.hadm_id
    GROUP BY
        pa.hadm_id
)
SELECT
    -- Calculate the median of the num_distinct_devices across all relevant hospitalizations.
    PERCENTILE_DISC(num_distinct_devices, 0.5) OVER() AS median_distinct_devices
FROM
    HadmsWithDeviceCounts
LIMIT 1; -- We only need one row as PERCENTILE_DISC without PARTITION BY returns a single value for the entire set.;