WITH base_cohort AS (
    -- Get first ICU stay for each admission of male patients aged 88-98
    SELECT 
        p.subject_id,
        p.anchor_age,
        i.hadm_id,
        i.stay_id,
        i.intime,
        i.outtime,
        i.los,
        adm.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON i.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON i.hadm_id = adm.hadm_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 88 AND 98
    QUALIFY ROW_NUMBER() OVER (PARTITION BY i.hadm_id ORDER BY i.intime) = 1
),
copd_cohort AS (
    -- Filter base_cohort for COPD exacerbation
    SELECT 
        b.*
    FROM base_cohort b
    WHERE EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE b.hadm_id = d.hadm_id
        AND (
            (d.icd_version = 10 AND d.icd_code IN ('J440', 'J441'))
            OR (d.icd_version = 9 AND d.icd_code IN ('49121', '49122'))
        )
    )
),
control_cohort AS (
    -- The rest of the base_cohort
    SELECT 
        b.*
    FROM base_cohort b
    WHERE NOT EXISTS (
        SELECT 1
        FROM copd_cohort c
        WHERE b.hadm_id = c.hadm_id
    )
),
procedure_counts AS (
    -- For each patient in COPD cohort, count distinct procedures in first 72h
    SELECT 
        c.stay_id,
        COUNT(DISTINCT p.itemid) AS num_procedures
    FROM copd_cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` p
        ON c.stay_id = p.stay_id
        AND p.starttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
    GROUP BY c.stay_id
),
copd_aggregates AS (
    SELECT
        'COPD Exacerbation' AS cohort,
        COUNT(*) AS num_patients,
        APPROX_QUANTILE(num_procedures, 0.75) AS percentile_75_procedures,
        AVG(los) AS mean_icu_los,
        AVG(hospital_expire_flag) AS in_hospital_mortality
    FROM copd_cohort
    LEFT JOIN procedure_counts USING (stay_id)
),
control_aggregates AS (
    SELECT
        'Control' AS cohort,
        COUNT(*) AS num_patients,
        NULL AS percentile_75_procedures,
        AVG(los) AS mean_icu_los,
        AVG(hospital_expire_flag) AS in_hospital_mortality
    FROM control_cohort
)
-- Main query
SELECT * FROM copd_aggregates
UNION ALL
SELECT * FROM control_aggregates;