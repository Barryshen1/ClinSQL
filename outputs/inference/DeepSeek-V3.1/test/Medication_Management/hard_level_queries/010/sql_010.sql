WITH cohort AS (
    SELECT 
        p.subject_id, 
        a.hadm_id, 
        p.anchor_age,
        a.admittime, 
        a.dischtime,
        a.hospital_expire_flag,
        -- Calculate next admission date for readmission
        LEAD(a.admittime) OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS next_admittime
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 61 AND 71
        AND a.admission_type = 'INPATIENT'
),

med_counts AS (
    SELECT 
        c.subject_id,
        c.hadm_id,
        COUNT(DISTINCT pr.drug) AS med_count
    FROM cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
        ON c.hadm_id = pr.hadm_id
        AND pr.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
    GROUP BY c.subject_id, c.hadm_id
),

cohort_with_meds AS (
    SELECT 
        c.*,
        COALESCE(m.med_count, 0) AS med_count,
        -- Calculate LOS in days
        DATETIME_DIFF(c.dischtime, c.admittime, DAY) AS los_days,
        -- Check for 30-day readmission
        CASE 
            WHEN c.next_admittime IS NOT NULL 
                AND DATETIME_DIFF(c.next_admittime, c.dischtime, DAY) <= 30 
            THEN 1 
            ELSE 0 
        END AS readmit_30d
    FROM cohort c
    LEFT JOIN med_counts m
        ON c.hadm_id = m.hadm_id
),

quintiles AS (
    SELECT 
        *,
        NTILE(5) OVER (ORDER BY med_count) AS quintile
    FROM cohort_with_meds
)

SELECT 
    quintile,
    COUNT(*) AS num_patients,
    AVG(med_count) AS mean_complexity_score,
    AVG(los_days) AS avg_los,
    AVG(hospital_expire_flag) AS in_hospital_mortality,
    AVG(readmit_30d) AS readmission_rate_30d
FROM quintiles
GROUP BY quintile
ORDER BY quintile;