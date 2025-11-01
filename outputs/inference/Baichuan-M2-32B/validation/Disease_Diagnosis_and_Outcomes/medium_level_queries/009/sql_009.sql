WITH cohort AS (
    SELECT 
        a.hadm_id,
        a.subject_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE p.gender = 'M'
        AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 53 AND 63
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
            WHERE d.hadm_id = a.hadm_id
                AND (d.icd_code LIKE 'A40.%' OR d.icd_code LIKE 'A41.%')
                AND d.icd_code <> 'A40.1'
        )
),
cohort_with_icu AS (
    SELECT 
        c.*,
        CASE 
            WHEN EXISTS (
                SELECT 1 
                FROM `physionet-data.mimiciv_3_1_icu.icustays` i
                WHERE i.hadm_id = c.hadm_id
                    AND DATE(i.intime) = DATE(c.admittime)
            ) THEN 1 
            ELSE 0 
        END AS day1_icu,
        DATE_DIFF(c.dischtime, c.admittime, DAY) AS los_days  -- Fixed function
    FROM cohort c
),
interventions AS (
    SELECT 
        c.hadm_id,
        c.hospital_expire_flag,
        c.los_days,
        c.day1_icu,
        CASE WHEN mv.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS mech_vent,
        CASE WHEN vp.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS vasopressor,
        CASE WHEN rrt.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS rrt
    FROM cohort_with_icu c
    LEFT JOIN (
        SELECT DISTINCT hadm_id
        FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
            ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
        WHERE d.long_title LIKE '%mechanical ventilation%' 
            OR d.long_title LIKE '%ventilator%'
    ) mv ON c.hadm_id = mv.hadm_id
    LEFT JOIN (
        SELECT DISTINCT hadm_id
        FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
        WHERE LOWER(drug) IN (
            'norepinephrine', 'epinephrine', 'dopamine', 'dobutamine', 
            'phenylephrine', 'vasopressin', 'isoproterenol', 'metaraminol', 'midodrine'
        )
    ) vp ON c.hadm_id = vp.hadm_id
    LEFT JOIN (
        SELECT DISTINCT hadm_id
        FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
            ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
        WHERE d.long_title LIKE '%dialysis%' 
            OR d.long_title LIKE '%CRRT%' 
            OR d.long_title LIKE '%renal replacement%'
    ) rrt ON c.hadm_id = rrt.hadm_id
)
SELECT 
    CASE 
        WHEN los_days < 8 THEN '<8' 
        ELSE '>=8' 
    END AS los_group,
    day1_icu,
    COUNT(*) AS total_admissions,
    AVG(hospital_expire_flag) * 100 AS mortality_percent,
    AVG(mech_vent) * 100 AS mech_vent_percent,
    AVG(vasopressor) * 100 AS vasopressor_percent,
    AVG(rrt) * 100 AS rrt_percent
FROM interventions
GROUP BY los_group, day1_icu
ORDER BY los_group, day1_icu;