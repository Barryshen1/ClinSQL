WITH cohort_stays AS (
        -- Step 1: Identify the main cohort of male ICU patients aged 77-87 admitted with asthma exacerbation.
        -- This CTE filters patients based on age, gender, and the presence of an asthma diagnosis
        -- during their hospital admission, and links them to their ICU stays.
        SELECT
            p.subject_id,
            ad.hadm_id,
            ad.admittime,
            ad.dischtime,
            ad.hospital_expire_flag,
            ic.stay_id,
            ic.intime
        FROM
            `physionet-data.mimiciv_3_1_hosp.patients` p
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.admissions` ad
            ON p.subject_id = ad.subject_id
        INNER JOIN
            `physionet-data.mimiciv_3_1_icu.icustays` ic
            ON ad.hadm_id = ic.hadm_id
        WHERE
            p.gender = 'M'
            AND p.anchor_age BETWEEN 77 AND 87
            -- Check for asthma diagnosis on this admission
            AND EXISTS (
                SELECT 1
                FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
                WHERE
                    di.hadm_id = ad.hadm_id
                    AND (
                        (di.icd_version = 9 AND di.icd_code LIKE '493%') OR -- ICD-9 codes for Asthma
                        (di.icd_version = 10 AND di.icd_code LIKE 'J45%')   -- ICD-10 codes for Asthma
                    )
            )
    ),
    icu_stay_procedure_counts AS (
        -- Step 2: Calculate the number of procedures performed within the first 72 hours of each
        -- eligible ICU stay. A LEFT JOIN is used to include stays with zero procedures.
        SELECT
            cs.subject_id,
            cs.hadm_id,
            cs.stay_id,
            cs.admittime,
            cs.dischtime,
            cs.intime,
            cs.hospital_expire_flag,
            COUNT(pe.stay_id) AS procedure_count_72hr -- Count of procedure events in the window
        FROM
            cohort_stays cs
        LEFT JOIN
            `physionet-data.mimiciv_3_1_icu.procedureevents` pe
            ON cs.stay_id = pe.stay_id
            -- Filter procedures to occur within the first 72 hours of ICU admission time (intime)
            AND pe.starttime >= cs.intime
            AND pe.starttime <= DATETIME_ADD(cs.intime, INTERVAL 72 HOUR)
        GROUP BY
            cs.subject_id, cs.hadm_id, cs.stay_id, cs.admittime, cs.dischtime, cs.intime, cs.hospital_expire_flag
    ),
    quartile_assigned_stays AS (
    -- Step 3: Calculate the hospital Length of Stay (LOS) in days for each admission
    -- and assign each ICU stay to a quartile based on their 72-hour procedure count.
    SELECT
        subject_id,
        hadm_id,
        stay_id,
        procedure_count_72hr,
        -- Calculate hospital LOS in days
        DATETIME_DIFF(dischtime, admittime, DAY) AS hospital_los_days,
        hospital_expire_flag,
        -- Assign quartile based on procedure count using NTILE(4)
        NTILE(4) OVER (ORDER BY procedure_count_72hr) AS procedure_quartile
    FROM
        icu_stay_procedure_counts
)
-- Step 4: Aggregate the results by the assigned procedure quartile, calculating
-- the mean procedure count, mean hospital LOS, and hospital mortality percentage for each.
SELECT
    procedure_quartile,
    AVG(procedure_count_72hr) AS mean_procedure_count,
    AVG(hospital_los_days) AS mean_hospital_los_days,
    AVG(hospital_expire_flag) * 100.0 AS hospital_mortality_percentage -- Simplified mortality calculation
FROM
    quartile_assigned_stays
GROUP BY
    procedure_quartile
ORDER BY
    procedure_quartile;