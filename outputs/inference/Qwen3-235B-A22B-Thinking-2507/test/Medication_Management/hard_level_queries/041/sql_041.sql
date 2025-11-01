WITH target_admissions AS (
    SELECT 
        a.hadm_id,
        a.subject_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE p.gender = 'M'
        AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 40 AND 50
        AND a.dischtime IS NOT NULL
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
            WHERE d.hadm_id = a.hadm_id
                AND (
                    (d.icd_version = 9 AND d.icd_code LIKE '428%')
                    OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
                )
        )
),
med_score AS (
    SELECT 
        ta.hadm_id,
        COUNT(DISTINCT p.drug) AS med_complexity_score
    FROM target_admissions ta
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p 
        ON ta.hadm_id = p.hadm_id
        AND p.starttime >= ta.admittime 
        AND p.starttime <= DATETIME_ADD(ta.admittime, INTERVAL 7 DAY)
    GROUP BY ta.hadm_id
),
admissions_with_next AS (
    SELECT 
        ta.*,
        LEAD(ta.admittime) OVER (PARTITION BY ta.subject_id ORDER BY ta.admittime) AS next_admittime
    FROM target_admissions ta
),
outcomes AS (
    SELECT 
        hadm_id,
        subject_id,
        admittime,
        dischtime,
        hospital_expire_flag,
        DATETIME_DIFF(dischtime, admittime, DAY) AS los_days,
        CASE 
            WHEN next_admittime <= DATETIME_ADD(dischtime, INTERVAL 30 DAY) THEN 1 
            ELSE 0 
        END AS readmission_30d
    FROM admissions_with_next
),
combined AS (
    SELECT 
        o.hadm_id,
        o.subject_id,
        o.los_days,
        o.hospital_expire_flag,
        o.readmission_30d,
        COALESCE(ms.med_complexity_score, 0) AS med_complexity_score
    FROM outcomes o
    LEFT JOIN med_score ms ON o.hadm_id = ms.hadm_id
),
quintiles AS (
    SELECT 
        *,
        NTILE(5) OVER (ORDER BY med_complexity_score) AS quintile
    FROM combined
)
SELECT 
    quintile,
    COUNT(*) AS patient_count,
    MIN(med_complexity_score) AS min_score,
    MAX(med_complexity_score) AS max_score,
    AVG(los_days) AS mean_los_days,
    AVG(hospital_expire_flag) AS in_hospital_mortality_rate,
    SUM(readmission_30d) / 
        NULLIF(SUM(CASE WHEN hospital_expire_flag = 0 THEN 1 ELSE 0 END), 0) 
        AS readmission_30d_rate
FROM quintiles
GROUP BY quintile
ORDER BY quintile;