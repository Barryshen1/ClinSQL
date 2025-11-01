WITH cohort AS (
    SELECT 
        p.subject_id, 
        p.gender, 
        p.anchor_age,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag AS mortality,
        DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
        CASE 
            WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) < 8 THEN '<8'
            ELSE '>=8'
        END AS los_group,
        CASE 
            WHEN COUNT(DISTINCT diag.icd_code) < 5 THEN 'low'
            WHEN COUNT(DISTINCT diag.icd_code) BETWEEN 5 AND 10 THEN 'medium'
            ELSE 'high'
        END AS comorbidity_burden,
        CASE WHEN i.stay_id IS NOT NULL THEN 'ICU' ELSE 'no ICU' END AS icu_status
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON a.hadm_id = diag.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
        ON a.hadm_id = i.hadm_id
    WHERE 
        p.gender = 'F'
        AND p.anchor_age BETWEEN 51 AND 61
        AND (
            (diag.icd_version = 9 AND diag.icd_code LIKE '428%') OR
            (diag.icd_version = 10 AND diag.icd_code LIKE 'I50%')
        )
    GROUP BY p.subject_id, p.gender, p.anchor_age, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag, i.stay_id
),

mv_patients AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
    WHERE itemid IN (227194, 225468, 225477)  -- Mechanical ventilation items
    UNION DISTINCT
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.chartevents`
    WHERE itemid IN (223848, 223849)  -- Ventilation mode
),

vaso_patients AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.inputevents`
    WHERE itemid IN (221906, 221289,  -- Norepinephrine, Epinephrine
                     221662, 221653)  -- Vasopressin, Phenylephrine
),

rrt_patients AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
    WHERE itemid IN (225441, 225802, 225803)  -- CRRT, Hemodialysis
)

SELECT 
    icu_status,
    los_group,
    comorbidity_burden,
    COUNT(*) AS n_patients,
    SUM(mortality) AS n_mortality,
    ROUND(SUM(mortality) * 100.0 / COUNT(*), 2) AS mortality_rate,
    ROUND(SUM(CASE WHEN mv.hadm_id IS NOT NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS mv_rate,
    ROUND(SUM(CASE WHEN vaso.hadm_id IS NOT NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS vaso_rate,
    ROUND(SUM(CASE WHEN rrt.hadm_id IS NOT NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS rrt_rate
FROM cohort c
LEFT JOIN mv_patients mv ON c.hadm_id = mv.hadm_id
LEFT JOIN vaso_patients vaso ON c.hadm_id = vaso.hadm_id
LEFT JOIN rrt_patients rrt ON c.hadm_id = rrt.hadm_id
GROUP BY icu_status, los_group, comorbidity_burden
ORDER BY icu_status, los_group, comorbidity_burden;