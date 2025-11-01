SELECT
    CASE
        WHEN admissions.hospital_expire_flag = 1 THEN 'In-hospital Mortality'
        ELSE 'Discharged Alive'
    END AS mortality_status,
    COUNT(admissions.hadm_id) AS n,
    ROUND(AVG(TIMESTAMP_DIFF(admissions.dischtime, admissions.admittime, DAY)), 2) AS mean_los_days,
    ROUND(APPROX_QUANTILES(TIMESTAMP_DIFF(admissions.dischtime, admissions.admittime, DAY), 100)[OFFSET(25)], 2) AS p25_los_days,
    ROUND(APPROX_QUANTILES(TIMESTAMP_DIFF(admissions.dischtime, admissions.admittime, DAY), 100)[OFFSET(50)], 2) AS p50_los_days, -- Median
    ROUND(APPROX_QUANTILES(TIMESTAMP_DIFF(admissions.dischtime, admissions.admittime, DAY), 100)[OFFSET(75)], 2) AS p75_los_days,
    ROUND(APPROX_QUANTILES(TIMESTAMP_DIFF(admissions.dischtime, admissions.admittime, DAY), 100)[OFFSET(90)], 2) AS p90_los_days
FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS admissions
INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS patients
    ON admissions.subject_id = patients.subject_id
WHERE
    patients.gender = 'F'
    AND patients.anchor_age BETWEEN 44 AND 54
    AND admissions.admission_type = 'ELECTIVE'
    AND admissions.dischtime IS NOT NULL -- Ensure discharge time exists for LOS calculation
    AND admissions.admittime IS NOT NULL -- Ensure admit time exists for LOS calculation
GROUP BY
    mortality_status
ORDER BY
    mortality_status;