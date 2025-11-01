WITH cohort_patients AS (
    -- Select the initial cohort: female, aged 87-97, with a lower GI bleeding diagnosis during their first ICU stay.
    SELECT DISTINCT
        p.subject_id,
        adm.hadm_id,
        icu.stay_id,
        icu.intime,
        icu.outtime,
        icu.los, -- LOS is already in days in icustays
        adm.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON p.subject_id = adm.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON adm.hadm_id = icu.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON icu.hadm_id = di.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
        ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 87 AND 97 -- MIMIC-IV caps anchor_age at 90 for >=90 y.o.
        AND (
            LOWER(TRIM(dicd.long_title)) LIKE '%gastrointestinal hemorrhage%'
            OR LOWER(TRIM(dicd.long_title)) LIKE '%melena%'
            OR di.icd_code IN ('5781', '5789', 'K921', 'K922') -- Specific ICD-9 and ICD-10 codes for GI bleeding (stored without decimals)
        )
        AND icu.intime = (SELECT MIN(icu2.intime) FROM `physionet-data.mimiciv_3_1_icu.icustays` icu2 WHERE icu2.subject_id = p.subject_id) -- Ensures it's the first ICU stay for the patient
),
patient_procedures_count AS (
    -- Count distinct procedures within the first 48 hours of ICU stay for each patient in the cohort.
    SELECT
        cp.subject_id,
        cp.hadm_id,
        cp.stay_id,
        cp.intime,
        cp.los,
        cp.hospital_expire_flag,
        COUNT(DISTINCT pe.itemid) AS distinct_procedure_count
    FROM
        cohort_patients cp
    LEFT JOIN
        `physionet-data.mimiciv_3_1_icu.procedureevents` pe
        ON cp.stay_id = pe.stay_id
        AND pe.starttime BETWEEN cp.intime AND TIMESTAMP_ADD(cp.intime, INTERVAL 48 HOUR)
    GROUP BY
        cp.subject_id, cp.hadm_id, cp.stay_id, cp.intime, cp.los, cp.hospital_expire_flag
),
patient_quintiles AS (
    -- Assign patients to quintiles based on their distinct procedure count.
    SELECT
        subject_id,
        hadm_id,
        stay_id,
        distinct_procedure_count,
        los,
        hospital_expire_flag,
        NTILE(5) OVER (ORDER BY distinct_procedure_count) AS procedure_quintile
    FROM
        patient_procedures_count
)
-- Final aggregation to report mean procedure count, mean ICU LOS, and in-hospital mortality % per quintile.
SELECT
    procedure_quintile,
    AVG(distinct_procedure_count) AS mean_procedure_count,
    AVG(los) AS mean_icu_los_days,
    AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_percent
FROM
    patient_quintiles
GROUP BY
    procedure_quintile
ORDER BY
    procedure_quintile;