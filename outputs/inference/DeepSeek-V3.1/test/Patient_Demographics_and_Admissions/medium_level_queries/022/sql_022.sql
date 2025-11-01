WITH patient_admissions AS (
    SELECT 
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.discharge_location,
        adm.hospital_expire_flag,
        pat.gender,
        pat.anchor_age,
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE 
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 81 AND 91
        AND adm.admission_location = 'TRANSFER FROM HOSPITAL'
        AND adm.dischtime IS NOT NULL  -- exclude ongoing admissions
),
discharge_groups AS (
    SELECT 
        CASE 
            WHEN hospital_expire_flag = 1 THEN 'IN-HOSPITAL DEATH'
            WHEN discharge_location = 'HOME' THEN 'HOME'
            WHEN discharge_location = 'HOSPICE' THEN 'HOSPICE'
        END AS discharge_category,
        los_days
    FROM patient_admissions
    WHERE 
        (hospital_expire_flag = 1 
         OR discharge_location = 'HOME' 
         OR discharge_location = 'HOSPICE')
)
SELECT 
    discharge_category,
    COUNT(*) AS n_patients,
    AVG(los_days) AS mean_los,
    APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS p25_los,
    APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los,
    APPROX_QUANTILES(los_days, 4)[OFFSET(3)] AS p75_los,
    APPROX_QUANTILES(los_days, 10)[OFFSET(9)] AS p90_los,
    ROUND(100 * SUM(CASE WHEN los_days <= 10 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_los_leq_10
FROM discharge_groups
GROUP BY discharge_category
ORDER BY discharge_category;