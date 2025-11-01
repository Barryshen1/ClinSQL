WITH SepsisCohort AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag,
        pat.gender,
        -- Calculate age at admission considering anchor year differences
        pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age_at_admission,
        -- Calculate hospital length of stay in days
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS hosp_los_days
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE
        pat.gender = 'M'
        -- Age must be between 53 and 63 at admission
        AND pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) BETWEEN 53 AND 63
        AND EXISTS (
            -- Check for sepsis diagnosis (ICD-10 codes A40.x or A41.x)
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_sepsis
            WHERE
                di_sepsis.hadm_id = adm.hadm_id
                AND di_sepsis.icd_version = 10
                AND (di_sepsis.icd_code LIKE 'A40%' OR di_sepsis.icd_code LIKE 'A41%')
        )
        AND NOT EXISTS (
            -- Exclude admissions with septic shock diagnosis (ICD-10 code R65.21)
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_shock
            WHERE
                di_shock.hadm_id = adm.hadm_id
                AND di_shock.icd_version = 10
                AND di_shock.icd_code = 'R6521' -- MIMIC-IV stores ICD codes without decimals. R65.21 becomes R6521.
        )
),
MV_Admissions AS (
    -- Identify admissions with Mechanical Ventilation
    SELECT DISTINCT ce.hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
        ON ce.itemid = di.itemid
    WHERE
        (
            -- Common itemids for ventilator settings
            ce.itemid IN (
                223848, -- Ventilator Mode
                220339, -- PEEP
                220210, -- Respiratory Rate
                224696, -- Plateau Pressure
                224738, -- Inspiratory Time
                224684, 224689, 224690, -- Tidal Volume related
                220212 -- FiO2
            )
            -- Or labels indicating ventilation-related care
            OR LOWER(di.label) LIKE '%ventilator mode%'
            OR LOWER(di.label) LIKE '%peep%'
            OR LOWER(di.label) LIKE '%tidal volume (set)%'
            OR LOWER(di.label) LIKE '%fio2%'
            OR LOWER(di.label) LIKE '%mechanical ventilation%' -- More general terms
            OR LOWER(di.label) LIKE '%ventilator settings%'
            OR LOWER(di.label) LIKE '%intubation%'
        )
),
VPA_Admissions AS (
    -- Identify admissions with Vasopressor administration
    SELECT DISTINCT ie.hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
    INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
        ON ie.itemid = di.itemid
    WHERE
        LOWER(di.label) LIKE '%norepinephrine%'
        OR LOWER(di.label) LIKE '%phenylephrine%'
        OR LOWER(di.label) LIKE '%epinephrine%'
        OR LOWER(di.label) LIKE '%vasopressin%'
        OR LOWER(di.label) LIKE '%dopamine%'
        OR LOWER(di.label) LIKE '%dobutamine%' -- Often included with vasopressors in clinical studies
),
RRT_Admissions AS (
    -- Identify admissions with Renal Replacement Therapy (RRT)
    SELECT DISTINCT picd.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` picd
    WHERE
        picd.icd_version = 10
        AND picd.icd_code IN ('5A1D00Z', '5A1D60Z') -- Hemodialysis, CRRT (ICD-10-PCS codes)
),
Day1_ICU_Admissions AS (
    -- Identify admissions with an ICU stay starting within the first 24 hours of hospital admission
    SELECT DISTINCT icu.hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm_ref -- Join to admissions table to get admittime for comparison
        ON icu.hadm_id = adm_ref.hadm_id
    WHERE
        icu.intime BETWEEN adm_ref.admittime AND DATETIME_ADD(adm_ref.admittime, INTERVAL 24 HOUR)
)
-- Now, join everything and calculate the final results
SELECT
    CASE
        WHEN sa.hosp_los_days < 8 THEN '< 8 Days'
        ELSE '>= 8 Days'
    END AS los_category,
    CASE
        WHEN d1icu.hadm_id IS NOT NULL THEN 'Day-1 ICU'
        ELSE 'No Day-1 ICU'
    END AS day1_icu_status,
    COUNT(DISTINCT sa.hadm_id) AS total_admissions,
    SAFE_DIVIDE(SUM(sa.hospital_expire_flag), COUNT(DISTINCT sa.hadm_id)) * 100 AS in_hospital_mortality_perc,
    SAFE_DIVIDE(COUNT(DISTINCT mv.hadm_id), COUNT(DISTINCT sa.hadm_id)) * 100 AS mech_vent_prevalence_perc,
    SAFE_DIVIDE(COUNT(DISTINCT vpa.hadm_id), COUNT(DISTINCT sa.hadm_id)) * 100 AS vasopressor_prevalence_perc,
    SAFE_DIVIDE(COUNT(DISTINCT rrt.hadm_id), COUNT(DISTINCT sa.hadm_id)) * 100 AS rrt_prevalence_perc
FROM
    SepsisCohort sa
LEFT JOIN
    MV_Admissions mv
    ON sa.hadm_id = mv.hadm_id
LEFT JOIN
    VPA_Admissions vpa
    ON sa.hadm_id = vpa.hadm_id
LEFT JOIN
    RRT_Admissions rrt
    ON sa.hadm_id = rrt.hadm_id
LEFT JOIN
    Day1_ICU_Admissions d1icu
    ON sa.hadm_id = d1icu.hadm_id
GROUP BY
    los_category,
    day1_icu_status
ORDER BY
    los_category,
    day1_icu_status;