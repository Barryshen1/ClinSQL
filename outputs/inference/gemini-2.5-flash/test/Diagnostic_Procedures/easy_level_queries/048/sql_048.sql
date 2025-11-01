WITH TargetPopulation AS (
    -- Select subject_id and hadm_id for males aged 52-62
    SELECT
        p.subject_id,
        adm.hadm_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON p.subject_id = adm.subject_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 52 AND 62
),
ValveProcedures AS (
    -- Identify all valve repair/replacement procedures for the target population
    SELECT
        tp.subject_id,
        tp.hadm_id,
        picd.icd_code
    FROM
        TargetPopulation tp
    JOIN
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` picd
        ON tp.subject_id = picd.subject_id
        AND tp.hadm_id = picd.hadm_id
    JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dicd
        ON picd.icd_code = dicd.icd_code
        AND picd.icd_version = dicd.icd_version
    WHERE
        LOWER(dicd.long_title) LIKE '%valve repair%'
        OR LOWER(dicd.long_title) LIKE '%valve replacement%'
),
DistinctValveProceduresPerHosp AS (
    -- Count distinct valve procedure codes per hospitalization
    SELECT
        subject_id,
        hadm_id,
        COUNT(DISTINCT icd_code) AS num_distinct_valve_procedures
    FROM
        ValveProcedures
    GROUP BY
        subject_id,
        hadm_id
)
-- Calculate the Interquartile Range (IQR)
SELECT
    PERCENTILE_DISC(num_distinct_valve_procedures, 0.75) OVER () -
    PERCENTILE_DISC(num_distinct_valve_procedures, 0.25) OVER () AS interquartile_range_of_distinct_valve_procedures
FROM
    DistinctValveProceduresPerHosp
QUALIFY ROW_NUMBER() OVER (ORDER BY 1) = 1; -- Ensure only a single result row;