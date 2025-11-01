WITH admissions_with_gi_bleeding AS (
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ad.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 53 AND 63
        AND EXISTS ( -- Ensure at least one upper GI bleeding diagnosis
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            WHERE
                di.subject_id = ad.subject_id
                AND di.hadm_id = ad.hadm_id
                AND (
                    -- ICD-9 codes for Upper GI Bleeding (MIMIC stores without dots)
                    (di.icd_version = 9 AND (
                        -- Peptic/Gastric/Duodenal ulcer with hemorrhage (e.g., 531.01 -> 53101, where 5th char is '1')
                        (LEFT(di.icd_code, 3) IN ('531', '532', '533', '534') AND SUBSTR(di.icd_code, 5, 1) = '1')
                        OR di.icd_code = '53085' -- Mallory-Weiss syndrome (530.85 -> 53085)
                        OR LEFT(di.icd_code, 3) = '578' -- Gastrointestinal hemorrhage (e.g., 578.0, 578.1, 578.9 -> 578x)
                    ))
                    OR
                    -- ICD-10 codes for Upper GI Bleeding (MIMIC stores without dots)
                    (di.icd_version = 10 AND (
                        -- Peptic/Gastric/Duodenal ulcer with hemorrhage (e.g., K25.0 -> K250, where 4th char is '0','2','4','6')
                        (LEFT(di.icd_code, 3) IN ('K25', 'K26', 'K27') AND SUBSTR(di.icd_code, 4, 1) IN ('0', '2', '4', '6'))
                        OR di.icd_code = 'K226' -- Mallory-Weiss syndrome (K22.6 -> K226)
                        OR LEFT(di.icd_code, 3) = 'K92' -- Gastrointestinal hemorrhage (e.g., K92.0, K92.1, K92.2 -> K92x)
                    ))
                )
        )
),
filtered_admissions AS (
    SELECT
        admb.hadm_id,
        -- Calculate stay duration in calendar days
        -- e.g., admittime=2000-01-01 10:00, dischtime=2000-01-02 09:00 -> DATE_DIFF = 1
        -- e.g., admittime=2000-01-01 10:00, dischtime=2000-01-01 23:00 -> DATE_DIFF = 0
        DATE_DIFF(CAST(admb.dischtime AS DATE), CAST(admb.admittime AS DATE), DAY) AS stay_duration_days,
        CASE
            WHEN DATE_DIFF(CAST(admb.dischtime AS DATE), CAST(admb.admittime AS DATE), DAY) BETWEEN 1 AND 4 THEN '1-4 Days'
            WHEN DATE_DIFF(CAST(admb.dischtime AS DATE), CAST(admb.admittime AS DATE), DAY) BETWEEN 5 AND 8 THEN '5-8 Days'
            ELSE 'Other' -- Safegard, but filtered out by outer WHERE
        END AS stay_duration_group
    FROM
        admissions_with_gi_bleeding admb
    WHERE
        DATE_DIFF(CAST(admb.dischtime AS DATE), CAST(admb.admittime AS DATE), DAY) BETWEEN 1 AND 8
),
-- Count diagnostic procedures for each admission
admission_procedure_counts AS (
    SELECT
        fa.hadm_id,
        fa.stay_duration_group,
        COUNT(p_icd.icd_code) AS num_procedures -- Counting all ICD procedures for the admission
    FROM
        filtered_admissions fa
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` p_icd
        ON fa.hadm_id = p_icd.hadm_id
    GROUP BY
        fa.hadm_id,
        fa.stay_duration_group
)
-- Calculate percentiles for num_procedures per stay_duration_group
SELECT
    apc.stay_duration_group,
    APPROX_QUANTILES(apc.num_procedures, 4)[OFFSET(1)] AS p25_procedures, -- Index 1 for 25th percentile
    APPROX_QUANTILES(apc.num_procedures, 4)[OFFSET(2)] AS p50_procedures, -- Index 2 for 50th percentile (median)
    APPROX_QUANTILES(apc.num_procedures, 4)[OFFSET(3)] AS p75_procedures  -- Index 3 for 75th percentile
FROM
    admission_procedure_counts apc
GROUP BY
    apc.stay_duration_group
ORDER BY
    apc.stay_duration_group;