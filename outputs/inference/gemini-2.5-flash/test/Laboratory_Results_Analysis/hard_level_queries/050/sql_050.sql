WITH
    -- 1. Identify ARDS patient admissions for female patients aged 40-50
    ards_cohort AS (
        SELECT DISTINCT
            p.subject_id,
            a.hadm_id,
            a.admittime,
            a.dischtime,
            a.hospital_expire_flag
        FROM
            `physionet-data.mimiciv_3_1_hosp.patients` AS p
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.admissions` AS a
            ON p.subject_id = a.subject_id
        WHERE
            p.gender = 'F'
            AND p.anchor_age BETWEEN 40 AND 50
            -- Filter for ARDS diagnosis using ICD codes
            AND EXISTS (
                SELECT
                    1
                FROM
                    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
                WHERE
                    di.hadm_id = a.hadm_id
                    AND (
                        (di.icd_version = 10 AND di.icd_code = 'J80') -- ARDS ICD-10
                        OR (di.icd_version = 9 AND di.icd_code = '51882') -- ARDS ICD-9
                    )
            )
    ),
    -- 2. Define critical lab item IDs used to determine instability
    -- These are common critical labs whose abnormal values often indicate physiological derangement
    critical_lab_itemids AS (
        SELECT
            itemid
        FROM
            UNNEST(
                [
                    50983, -- Sodium
                    50971, -- Potassium
                    50912, -- Creatinine
                    51301, -- White Blood Cell Count
                    51221, -- Hemoglobin
                    50931, -- Glucose
                    51265 -- Platelet Count
                ]
            ) AS itemid
    ),
    -- 3. Get all abnormal lab events for ARDS cohort within the first 72 hours of admission
    ardscohort_abnormal_lab_events_72h AS (
        SELECT
            ac.subject_id,
            ac.hadm_id,
            le.labevent_id
        FROM
            ards_cohort AS ac
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.labevents` AS le
            ON ac.subject_id = le.subject_id
            AND ac.hadm_id = le.hadm_id
        INNER JOIN
            critical_lab_itemids AS cli
            ON le.itemid = cli.itemid
        WHERE
            -- Lab event occurred within the first 72 hours of admission
            le.charttime BETWEEN ac.admittime AND DATETIME_ADD(ac.admittime, INTERVAL 72 HOUR)
            -- Numeric value must exist and reference ranges must be available
            AND le.valuenum IS NOT NULL
            AND le.ref_range_lower IS NOT NULL
            AND le.ref_range_upper IS NOT NULL
            -- Value is outside the defined reference range (abnormal)
            AND (
                le.valuenum < le.ref_range_lower
                OR le.valuenum > le.ref_range_upper
            )
    ),
    -- 4. Calculate lab instability scores for each admission in the ARDS cohort
    ards_instability_scores AS (
        SELECT
            ac.subject_id,
            ac.hadm_id,
            ac.admittime,
            ac.dischtime,
            ac.hospital_expire_flag,
            -- Count distinct abnormal lab events as the instability score. COALESCE handles admissions with no abnormal labs.
            COALESCE(COUNT(DISTINCT aale.labevent_id), 0) AS lab_instability_score
        FROM
            ards_cohort AS ac
        LEFT JOIN
            ardscohort_abnormal_lab_events_72h AS aale
            ON ac.hadm_id = aale.hadm_id
        GROUP BY
            ac.subject_id,
            ac.hadm_id,
            ac.admittime,
            ac.dischtime,
            ac.hospital_expire_flag
    ),
    -- 5. Determine the 75th percentile of the lab instability score for the entire ARDS cohort
    percentile_threshold AS (
        SELECT
            PERCENTILE_CONT(ais.lab_instability_score, 0.75) OVER () AS p75_score
        FROM
            ards_instability_scores AS ais
        LIMIT 1 -- Only need one value for the percentile
    ),
    -- 6. Filter ARDS patients whose instability score is at or above the 75th percentile
    ards_high_instability AS (
        SELECT
            ais.subject_id,
            ais.hadm_id,
            ais.admittime,
            ais.dischtime,
            ais.hospital_expire_flag,
            ais.lab_instability_score
        FROM
            ards_instability_scores AS ais,
            percentile_threshold AS pt
        WHERE
            ais.lab_instability_score >= pt.p75_score
    ),
    -- 7. Identify age-matched non-ARDS patient admissions (same age/gender, but no ARDS diagnosis)
    non_ards_cohort AS (
        SELECT DISTINCT
            p.subject_id,
            a.hadm_id,
            a.admittime,
            a.dischtime
        FROM
            `physionet-data.mimiciv_3_1_hosp.patients` AS p
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.admissions` AS a
            ON p.subject_id = a.subject_id
        WHERE
            p.gender = 'F'
            AND p.anchor_age BETWEEN 40 AND 50
            -- Exclude ARDS diagnosis
            AND NOT EXISTS (
                SELECT
                    1
                FROM
                    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
                WHERE
                    di.hadm_id = a.hadm_id
                    AND (
                        (di.icd_version = 10 AND di.icd_code = 'J80')
                        OR (di.icd_version = 9 AND di.icd_code = '51882')
                    )
            )
            -- Exclude any hadm_id that was explicitly identified in the ARDS cohort
            AND a.hadm_id NOT IN (SELECT hadm_id FROM ards_cohort)
    ),
    -- 8. Get all abnormal lab events for non-ARDS cohort within the first 72 hours
    non_ardscohort_abnormal_lab_events_72h AS (
        SELECT
            nac.subject_id,
            nac.hadm_id,
            le.labevent_id
        FROM
            non_ards_cohort AS nac
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.labevents` AS le
            ON nac.subject_id = le.subject_id
            AND nac.hadm_id = le.hadm_id
        INNER JOIN
            critical_lab_itemids AS cli
            ON le.itemid = cli.itemid
        WHERE
            le.charttime BETWEEN nac.admittime AND DATETIME_ADD(nac.admittime, INTERVAL 72 HOUR)
            AND le.valuenum IS NOT NULL
            AND le.ref_range_lower IS NOT NULL
            AND le.ref_range_upper IS NOT NULL
            AND (
                le.valuenum < le.ref_range_lower
                OR le.valuenum > le.ref_range_upper
            )
    ),
    -- 9. Calculate lab instability scores for each admission in the non-ARDS cohort
    non_ards_instability_scores AS (
        SELECT
            nac.subject_id,
            nac.hadm_id,
            COALESCE(COUNT(DISTINCT nale.labevent_id), 0) AS lab_instability_score
        FROM
            non_ards_cohort AS nac
        LEFT JOIN
            non_ardscohort_abnormal_lab_events_72h AS nale
            ON nac.hadm_id = nale.hadm_id
        GROUP BY
            nac.subject_id,
            nac.hadm_id
    )
-- Final aggregation of results
SELECT
    (SELECT pt.p75_score FROM percentile_threshold AS pt) AS ards_75th_percentile_instability_score,
    (
        SELECT
            AVG(ahis.hospital_expire_flag)
        FROM
            ards_high_instability AS ahis
    ) AS ards_high_instability_mortality_rate,
    (
        SELECT
            AVG(DATETIME_DIFF(ahis.dischtime, ahis.admittime, HOUR) / 24.0)
        FROM
            ards_high_instability AS ahis
    ) AS ards_high_instability_mean_los_days,
    (
        SELECT
            AVG(ahis.lab_instability_score)
        FROM
            ards_high_instability AS ahis
    ) AS ards_high_instability_avg_critical_lab_events_per_patient,
    (
        SELECT
            AVG(nais.lab_instability_score)
        FROM
            non_ards_instability_scores AS nais
    ) AS non_ards_avg_critical_lab_events_per_patient;