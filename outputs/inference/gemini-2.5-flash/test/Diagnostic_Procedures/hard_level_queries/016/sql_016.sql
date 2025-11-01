WITH patients_filtered AS (
    -- Step 1: Filter patients by gender and age
    SELECT
        p.subject_id
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 88 AND 98
),
first_icu_stay AS (
    -- Step 2: Identify the first ICU stay for eligible patients, and related admission/ICU stay details
    SELECT
        pf.subject_id,
        adm.hadm_id,
        icu.stay_id,
        icu.intime,
        icu.los,
        adm.hospital_expire_flag,
        ROW_NUMBER() OVER (PARTITION BY pf.subject_id ORDER BY icu.intime) AS rn
    FROM
        patients_filtered pf
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON pf.subject_id = adm.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON adm.hadm_id = icu.hadm_id
),
first_icu_for_analysis AS (
    -- Selecting only the first ICU stay for each patient
    SELECT
        subject_id,
        hadm_id,
        stay_id,
        intime,
        los,
        hospital_expire_flag
    FROM
        first_icu_stay
    WHERE
        rn = 1
),
pneumonia_admissions AS (
    -- Step 3: Filter for admissions with a pneumonia diagnosis
    SELECT
        f.subject_id,
        f.hadm_id,
        f.stay_id,
        f.intime,
        f.los,
        f.hospital_expire_flag
    FROM
        first_icu_for_analysis f
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON f.hadm_id = di.hadm_id
    WHERE
        -- ICD-9 codes for pneumonia: 480-486
        (di.icd_version = 9 AND SUBSTR(di.icd_code, 1, 3) BETWEEN '480' AND '486')
        -- ICD-10 codes for pneumonia: J12-J18
        OR (di.icd_version = 10 AND SUBSTR(di.icd_code, 1, 3) BETWEEN 'J12' AND 'J18')
    GROUP BY
        f.subject_id, f.hadm_id, f.stay_id, f.intime, f.los, f.hospital_expire_flag
),
procedures_72hr AS (
    -- Step 4: Calculate 72-hour diagnostic procedure counts for these patients
    SELECT
        pa.stay_id,
        COUNT(DISTINCT picd.icd_code) AS procedure_count_72hr
    FROM
        pneumonia_admissions pa
    LEFT JOIN -- Use LEFT JOIN to include patients who might not have any procedures in this window
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` picd
        ON pa.hadm_id = picd.hadm_id
        AND picd.chartdate >= DATE(pa.intime)
        AND picd.chartdate < DATE(TIMESTAMP_ADD(pa.intime, INTERVAL 72 HOUR))
    GROUP BY
        pa.stay_id
),
data_with_quintiles AS (
    -- Step 5: Combine all data and assign quintiles based on procedure count
    SELECT
        pa.subject_id,
        pa.hadm_id,
        pa.stay_id,
        pa.los,
        pa.hospital_expire_flag,
        COALESCE(p72.procedure_count_72hr, 0) AS procedure_count_72hr, -- Treat NULL procedure counts as 0
        NTILE(5) OVER (ORDER BY COALESCE(p72.procedure_count_72hr, 0) ASC) AS procedure_quintile
    FROM
        pneumonia_admissions pa
    LEFT JOIN
        procedures_72hr p72
        ON pa.stay_id = p72.stay_id
)
-- Step 6: Calculate final metrics per quintile
SELECT
    procedure_quintile,
    COUNT(DISTINCT stay_id) AS num_icu_stays_in_quintile,
    AVG(procedure_count_72hr) AS average_procedure_count_72hr,
    AVG(los) AS average_icu_los_days,
    AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_percent
FROM
    data_with_quintiles
WHERE
    procedure_quintile IS NOT NULL -- Ensure that partitions with insufficient data for NTILE are not included
GROUP BY
    procedure_quintile
ORDER BY
    procedure_quintile;