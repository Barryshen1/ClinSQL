WITH cohort AS (
    SELECT 
        p.subject_id,
        a.hadm_id,
        a.hospital_expire_flag,
        DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
        CASE WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) <= 7 THEN '<=7' ELSE '>7' END AS los_group,
        MAX(CASE WHEN icu.intime BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 24 HOUR) THEN 1 ELSE 0 END) AS in_icu_day1
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON a.hadm_id = diag.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON a.hadm_id = icu.hadm_id
    WHERE 
        p.gender = 'F'
        AND p.anchor_age BETWEEN 79 AND 89
        AND a.admission_type = 'EMERGENCY'
        AND (d.icd_code LIKE 'J13%' OR 
             d.icd_code LIKE 'J14%' OR 
             d.icd_code LIKE 'J15%' OR 
             d.icd_code LIKE 'J16%' OR 
             d.icd_code LIKE 'J17%' OR 
             d.icd_code LIKE 'J18%' OR 
             d.icd_code = 'J69.0')
    GROUP BY p.subject_id, a.hadm_id, a.hospital_expire_flag, a.admittime, a.dischtime
),

mech_vent AS (
    SELECT 
        hadm_id,
        MAX(1) AS mech_vent_flag
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents` p
    WHERE itemid IN (227194, 225468, 225477, 225792, 225794, 225798, 225796, 225772)
    GROUP BY hadm_id
),

vasopressor AS (
    SELECT 
        hadm_id,
        MAX(1) AS vasopressor_flag
    FROM `physionet-data.mimiciv_3_1_icu.inputevents` i
    WHERE itemid IN (221906, 221289, 222315)
    GROUP BY hadm_id
),

rrt AS (
    SELECT 
        hadm_id,
        MAX(1) AS rrt_flag
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents` p
    WHERE itemid IN (225802, 225803, 225809, 225805, 225810, 225812, 225814)
    GROUP BY hadm_id
)

SELECT 
    los_group,
    in_icu_day1,
    COUNT(*) AS n_patients,
    ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS mortality_percent,
    ROUND(SUM(COALESCE(mech_vent_flag, 0)) * 100.0 / COUNT(*), 2) AS mech_vent_percent,
    ROUND(SUM(COALESCE(vasopressor_flag, 0)) * 100.0 / COUNT(*), 2) AS vasopressor_percent,
    ROUND(SUM(COALESCE(rrt_flag, 0)) * 100.0 / COUNT(*), 2) AS rrt_percent
FROM cohort
LEFT JOIN mech_vent USING (hadm_id)
LEFT JOIN vasopressor USING (hadm_id)
LEFT JOIN rrt USING (hadm_id)
GROUP BY los_group, in_icu_day1
ORDER BY los_group, in_icu_day1;