WITH cohort_raw AS (
    -- Select eligible patients and their first ICU stay information
    SELECT
        ad.subject_id,
        ad.hadm_id,
        icu.stay_id,
        icu.intime,
        icu.los,
        ad.hospital_expire_flag,
        -- Rank ICU stays to identify the first for each admission
        ROW_NUMBER() OVER (PARTITION BY ad.subject_id, ad.hadm_id ORDER BY icu.intime) AS rn
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON ad.subject_id = pat.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` AS icu
        ON ad.hadm_id = icu.hadm_id
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 37 AND 47
        AND EXISTS ( -- Check for pneumonia diagnosis during the admission
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
            WHERE di.hadm_id = ad.hadm_id
                AND (
                    (di.icd_version = 10 AND di.icd_code LIKE 'J1[0-8]%') -- ICD-10 codes for pneumonia (J10-J18)
                    OR
                    (di.icd_version = 9 AND LEFT(di.icd_code, 3) BETWEEN '480' AND '487') -- ICD-9 codes for pneumonia (480.x-487.x)
                )
        )
),
first_icu_pneumonia_patients AS (
    -- Filter for only the first ICU stay of the admission
    SELECT
        subject_id,
        hadm_id,
        stay_id,
        intime,
        los,
        hospital_expire_flag
    FROM
        cohort_raw
    WHERE
        rn = 1
),
patient_procedures_48hr AS (
    -- Count distinct procedures within the first 48 hours of ICU stay for each patient
    SELECT
        pfp.subject_id,
        pfp.hadm_id,
        pfp.stay_id,
        pfp.los,
        pfp.hospital_expire_flag,
        COUNT(DISTINCT pe.itemid) AS procedure_count_48hr -- Count distinct procedures
    FROM
        first_icu_pneumonia_patients AS pfp
    LEFT JOIN
        `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
        ON pfp.stay_id = pe.stay_id
        AND pe.starttime BETWEEN pfp.intime AND TIMESTAMP_ADD(pfp.intime, INTERVAL 48 HOUR)
    GROUP BY
        pfp.subject_id, pfp.hadm_id, pfp.stay_id, pfp.los, pfp.hospital_expire_flag
),
quintiles_assigned AS (
    -- Assign quintiles based on the procedure count
    SELECT
        subject_id,
        hadm_id,
        stay_id,
        los,
        hospital_expire_flag,
        procedure_count_48hr,
        NTILE(5) OVER (ORDER BY procedure_count_48hr ASC) AS procedure_quintile
    FROM
        patient_procedures_48hr
)
-- Calculate mean procedure count, mean ICU LOS, and hospital mortality percent by quintile
SELECT
    procedure_quintile,
    CAST(AVG(procedure_count_48hr) AS BIGNUMERIC) AS mean_distinct_procedure_count,
    CAST(AVG(los) AS BIGNUMERIC) AS mean_icu_los_days,
    CAST(AVG(hospital_expire_flag) * 100 AS BIGNUMERIC) AS hospital_mortality_percent
FROM
    quintiles_assigned
WHERE
    procedure_quintile IS NOT NULL -- Safely exclude any rows that might not be assigned a quintile (e.g., if there are very few valid rows overall for NTILE)
GROUP BY
    procedure_quintile
ORDER BY
    procedure_quintile;