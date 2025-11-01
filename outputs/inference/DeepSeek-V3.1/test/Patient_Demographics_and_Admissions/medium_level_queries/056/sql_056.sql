WITH cohort AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag,
        -- Calculate length of stay in days
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los,
        -- Define discharge status: alive or died
        CASE WHEN adm.hospital_expire_flag = 1 THEN 'died' ELSE 'alive' END AS discharge_status
    FROM `physionet-data.mimiciv_3_1_hosp.patients` pat
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON pat.subject_id = adm.subject_id
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 67 AND 77
        AND adm.admission_location = 'EMERGENCY ROOM'
        AND adm.admission_type LIKE '%INPATIENT%'
        AND adm.dischtime IS NOT NULL
)
SELECT
    discharge_status,
    COUNT(*) AS total_patients,
    AVG(CASE WHEN los >= 7 THEN 1.0 ELSE 0.0 END) AS proportion_los_ge_7_days,
    AVG(CASE WHEN los >= 14 THEN 1.0 ELSE 0.0 END) AS proportion_los_ge_14_days,
    AVG(CASE WHEN los <= 10 THEN 1.0 ELSE 0.0 END) AS percentile_rank_10_day_los
FROM cohort
GROUP BY discharge_status
ORDER BY discharge_status;