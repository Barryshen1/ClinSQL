WITH base_cohort AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        icu.stay_id,
        adm.admittime,
        adm.dischtime,
        icu.intime,
        adm.hospital_expire_flag,
        -- Calculate age at admission
        p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_at_admission,
        -- Calculate hospital LOS in days (with fractional part)
        TIMESTAMP_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS hospital_los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON adm.subject_id = p.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` AS icu
        ON adm.hadm_id = icu.hadm_id AND adm.subject_id = icu.subject_id
    WHERE
        p.gender = 'M'
        AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 82 AND 92
        AND adm.dischtime IS NOT NULL -- Ensure dischtime exists for valid LOS calculation
        AND adm.admittime IS NOT NULL -- Ensure admittime exists for valid LOS calculation
    AND EXISTS ( -- Check for cardiogenic shock diagnosis within this admission
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
        WHERE diag.hadm_id = adm.hadm_id
        AND (
               (diag.icd_code = 'R570' AND diag.icd_version = 10) -- ICD-10: Cardiogenic shock
            OR (diag.icd_code = '78551' AND diag.icd_version = 9) -- ICD-9: Cardiogenic Shock
        )
    )
),
-- Calculate first-24-hour procedure burden for each ICU stay
procedures_24hr AS (
    SELECT
        bc.stay_id,
        COUNT(pe.itemid) AS procedure_count_24hr
    FROM
        base_cohort AS bc
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
        ON bc.stay_id = pe.stay_id
    WHERE
        pe.starttime IS NOT NULL
        AND pe.starttime >= bc.intime
        AND pe.starttime < TIMESTAMP_ADD(bc.intime, INTERVAL 24 HOUR)
    GROUP BY
        bc.stay_id
),
-- Combine base cohort info with procedure count, handling zero procedures
final_cohort_with_proc_count AS (
    SELECT
        bc.subject_id,
        bc.hadm_id,
        bc.stay_id,
        bc.hospital_los_days,
        bc.hospital_expire_flag,
        COALESCE(p24.procedure_count_24hr, 0) AS procedure_count_24hr
    FROM
        base_cohort AS bc
    LEFT JOIN
        procedures_24hr AS p24
        ON bc.stay_id = p24.stay_id
),
-- Assign quintiles based on first-24-hour procedure burden
quintiled_population AS (
    SELECT
        subject_id,
        hadm_id,
        stay_id,
        hospital_los_days,
        hospital_expire_flag,
        procedure_count_24hr,
        NTILE(5) OVER (ORDER BY procedure_count_24hr) AS procedure_quintile
    FROM
        final_cohort_with_proc_count
)
-- Aggregate results by quintile
SELECT
    procedure_quintile,
    AVG(procedure_count_24hr) AS mean_procedure_count,
    AVG(hospital_los_days) AS mean_hospital_los_days,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS mortality_percentage
FROM
    quintiled_population
GROUP BY
    procedure_quintile
ORDER BY
    procedure_quintile;