WITH
-- CTE 1: Find hospital admissions (hadm_id) with a diagnosis of HHS
hhs_hadms AS (
    SELECT DISTINCT dx.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
        ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
    WHERE
        -- Find diagnoses related to Hyperglycemic Hyperosmolar State (HHS)
        LOWER(d_dx.long_title) LIKE '%hyperosmolar%'
),

-- CTE 2: Identify the cohort of ICU stays for male patients aged 66-76 with HHS
cohort_stays AS (
    SELECT
        icu.subject_id,
        icu.hadm_id,
        icu.stay_id,
        icu.intime
    FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON icu.subject_id = p.subject_id
    -- Filter for hospital admissions with an HHS diagnosis
    INNER JOIN hhs_hadms
        ON icu.hadm_id = hhs_hadms.hadm_id
    WHERE
        p.gender = 'M'
        -- Calculate age at ICU admission and filter for the 66-76 age range
        AND ((EXTRACT(YEAR FROM icu.intime) - p.anchor_year) + p.anchor_age) BETWEEN 66 AND 76
),

-- CTE 3: Count procedures within the first 48 hours of each ICU stay for the cohort
proc_counts AS (
    SELECT
        cs.subject_id,
        cs.hadm_id,
        cs.stay_id,
        -- Count procedures that start within the first 48 hours of the ICU stay
        COUNT(pe.itemid) AS procedure_count
    FROM cohort_stays AS cs
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
        ON cs.stay_id = pe.stay_id
        AND pe.starttime BETWEEN cs.intime AND DATETIME_ADD(cs.intime, INTERVAL 48 HOUR)
    GROUP BY
        cs.subject_id, cs.hadm_id, cs.stay_id
),

-- CTE 4: Augment admissions data with LOS and 30-day readmission flag for cohort patients
admissions_augmented AS (
    SELECT
        hadm_id,
        subject_id,
        admittime,
        dischtime,
        hospital_expire_flag,
        -- Calculate hospital length of stay in days
        DATETIME_DIFF(dischtime, admittime, DAY) AS hospital_los_days,
        -- Determine if a readmission occurred within 30 days of discharge
        CASE
            WHEN
                DATETIME_DIFF(
                    LEAD(admittime, 1) OVER (PARTITION BY subject_id ORDER BY admittime),
                    dischtime,
                    DAY
                ) <= 30
                THEN 1
            ELSE 0
        END AS is_readmitted_30_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
    -- Optimization: Only process admissions for patients in our cohort
    WHERE subject_id IN (SELECT DISTINCT subject_id FROM cohort_stays)
),

-- CTE 5: Combine stay-level procedure counts with admission-level outcomes
-- and assign quintiles based on procedure count
data_with_quintiles AS (
    SELECT
        pc.stay_id,
        pc.procedure_count,
        adm.hospital_expire_flag,
        adm.hospital_los_days,
        adm.is_readmitted_30_days,
        -- Stratify by procedure count into 5 groups (quintiles)
        NTILE(5) OVER (ORDER BY pc.procedure_count) AS procedure_quintile
    FROM proc_counts AS pc
    INNER JOIN admissions_augmented AS adm
        ON pc.hadm_id = adm.hadm_id
)

-- Final step: Group by quintile and calculate the requested metrics
SELECT
    procedure_quintile,
    COUNT(stay_id) AS number_of_icu_stays,
    ROUND(AVG(procedure_count), 2) AS mean_procedures,
    MIN(procedure_count) AS min_procedures,
    MAX(procedure_count) AS max_procedures,
    ROUND(AVG(CAST(hospital_expire_flag AS BIGNUMERIC)) * 100, 2) AS hospital_mortality_pct,
    ROUND(AVG(hospital_los_days), 2) AS mean_hospital_los_days,
    ROUND(AVG(CAST(is_readmitted_30_days AS BIGNUMERIC)) * 100, 2) AS readmission_30_day_pct
FROM data_with_quintiles
GROUP BY
    procedure_quintile
ORDER BY
    procedure_quintile;