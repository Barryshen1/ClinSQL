WITH sepsis_cohort AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id, 
        adm.admittime, 
        adm.dischtime, 
        adm.hospital_expire_flag,
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los,
        -- Check if day1 ICU: exists an ICU stay starting within 24 hours of admission
        CASE WHEN EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_icu.icustays` icu 
            WHERE icu.hadm_id = adm.hadm_id 
            AND icu.intime <= DATETIME_ADD(adm.admittime, INTERVAL 1 DAY)
        ) THEN 1 ELSE 0 END AS day1_icu,
        -- Check for mechanical ventilation
        CASE WHEN EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
            WHERE proc.hadm_id = adm.hadm_id 
            AND proc.icd_code LIKE '5A195%'
        ) THEN 1 ELSE 0 END AS mech_vent_flag,
        -- Check for vasopressors (using inputevents in ICU)
        CASE WHEN EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_icu.inputevents` inp
            JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON inp.itemid = di.itemid
            WHERE inp.hadm_id = adm.hadm_id
            AND di.label IN ('Norepinephrine', 'Epinephrine', 'Vasopressin', 'Dopamine', 'Phenylephrine')
        ) THEN 1 ELSE 0 END AS vasopressor_flag,
        -- Check for RRT
        CASE WHEN EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
            WHERE proc.hadm_id = adm.hadm_id 
            AND proc.icd_code LIKE '5A1D%'
        ) THEN 1 ELSE 0 END AS rrt_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat 
        ON adm.subject_id = pat.subject_id
    WHERE pat.gender = 'M'
        AND pat.anchor_age BETWEEN 53 AND 63
        -- Sepsis without septic shock: has sepsis code and no septic shock code
        AND EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
            WHERE diag.hadm_id = adm.hadm_id 
            AND diag.icd_code LIKE 'A41%'
        )
        AND NOT EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
            WHERE diag.hadm_id = adm.hadm_id 
            AND diag.icd_code = 'R65.21'
            AND diag.icd_version = 10
        )
)

SELECT 
    CASE WHEN los < 8 THEN '<8' ELSE '>=8' END AS los_group,
    day1_icu,
    COUNT(*) AS n_admissions,
    ROUND(100 * AVG(hospital_expire_flag), 2) AS mortality_percent,
    ROUND(100 * AVG(mech_vent_flag), 2) AS mech_vent_percent,
    ROUND(100 * AVG(vasopressor_flag), 2) AS vasopressor_percent,
    ROUND(100 * AVG(rrt_flag), 2) AS rrt_percent
FROM sepsis_cohort
GROUP BY los_group, day1_icu
ORDER BY los_group, day1_icu;