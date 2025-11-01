WITH cohort AS (
    SELECT 
        a.hadm_id,
        DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los,
        CASE 
            WHEN a.hospital_expire_flag = 1 THEN 'Mortality'
            WHEN a.discharge_location = 'HOME' THEN 'Home'
            ELSE 'Facility'
        END AS outcome_group
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE 
        p.gender = 'M'
        AND p.anchor_age BETWEEN 67 AND 77
        AND EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_hosp.services` s 
            WHERE s.hadm_id = a.hadm_id 
            AND s.curr_service LIKE '%SURG%'
        )
)

SELECT 
    outcome_group,
    COUNT(*) AS num_patients,
    ROUND(AVG(los), 2) AS mean_los,
    ROUND(STDDEV(los), 2) AS sd_los,
    ROUND(100.0 * SUM(CASE WHEN los <= 7 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_los_leq_7
FROM cohort
GROUP BY outcome_group
ORDER BY outcome_group;