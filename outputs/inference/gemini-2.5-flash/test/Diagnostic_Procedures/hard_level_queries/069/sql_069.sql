WITH cohort_patients AS (
    SELECT
        pa.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag,
        ic.stay_id,
        ic.intime AS icu_intime
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` pa
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
        ON pa.subject_id = ad.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` ic
        ON ad.hadm_id = ic.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON ad.hadm_id = di.hadm_id
    WHERE
        pa.gender = 'M'
        AND pa.anchor_age BETWEEN 44 AND 54
        AND di.seq_num = 1 -- Primary diagnosis
        AND (
            -- ICD-9 code for Pulmonary Embolism
            (di.icd_version = 9 AND di.icd_code = '4151') OR
            -- ICD-10 codes for Pulmonary Embolism (I26.0xx, I26.9xx)
            (di.icd_version = 10 AND di.icd_code LIKE 'I26%')
        )
),
-- Select the first ICU stay for each qualifying hospital admission
first_icu_stay_per_hadm AS (
    SELECT
        subject_id,
        hadm_id,
        admittime,
        dischtime,
        hospital_expire_flag,
        stay_id,
        icu_intime,
        ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY icu_intime) AS rn
    FROM
        cohort_patients
),
-- Calculate distinct procedures within first 72 hours and hospital LOS for each patient's first ICU stay
patient_summary AS (
    SELECT
        fis.subject_id,
        fis.hadm_id,
        fis.stay_id,
        fis.hospital_expire_flag,
        DATETIME_DIFF(fis.dischtime, fis.admittime, HOUR) / 24.0 AS hospital_los_days,
        -- Count distinct procedures. Grouping by (subject_id, hadm_id, stay_id) and then LEFT JOINing means if no procedures, count will be 0.
        COUNT(DISTINCT pe.itemid) AS distinct_procedure_count -- Count distinct item IDs
    FROM
        first_icu_stay_per_hadm fis
    LEFT JOIN
        `physionet-data.mimiciv_3_1_icu.procedureevents` pe
        ON fis.stay_id = pe.stay_id
        AND pe.starttime BETWEEN fis.icu_intime AND DATETIME_ADD(fis.icu_intime, INTERVAL 72 HOUR)
    WHERE
        fis.rn = 1
    GROUP BY
        fis.subject_id, fis.hadm_id, fis.stay_id, fis.hospital_expire_flag, fis.admittime, fis.dischtime
),
-- Assign quintiles based on distinct procedure count
quintiled_patients AS (
    SELECT
        subject_id,
        hadm_id,
        stay_id,
        hospital_expire_flag,
        hospital_los_days,
        distinct_procedure_count,
        NTILE(5) OVER (ORDER BY distinct_procedure_count) AS diagnostic_intensity_quintile
    FROM
        patient_summary
)
-- Aggregate results by diagnostic intensity quintile
SELECT
    diagnostic_intensity_quintile,
    AVG(distinct_procedure_count) AS average_procedure_count,
    AVG(hospital_los_days) AS average_hospital_los_days,
    -- Calculate mortality percentage
    AVG(CASE WHEN hospital_expire_flag = 1 THEN 1.0 ELSE 0.0 END) * 100 AS mortality_percentage
FROM
    quintiled_patients
GROUP BY
    diagnostic_intensity_quintile
ORDER BY
    diagnostic_intensity_quintile;