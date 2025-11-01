SELECT
    CASE
        WHEN a.hospital_expire_flag = 1 THEN 'In-hospital Death'
        WHEN a.discharge_location = 'HOME' THEN 'Discharged Home'
        WHEN a.discharge_location = 'HOSPICE' THEN 'Discharged to Hospice'
        ELSE 'Other Discharge' -- Catches SNF, LTACH, etc., not explicitly requested
    END AS discharge_status,
    AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0) AS mean_los_days,
    STDDEV(TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0) AS stddev_los_days
FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 63 AND 73
    AND a.admission_location = 'TRANSFER FROM OTHER HEAL FACIL'
    AND a.admittime IS NOT NULL -- Ensure valid admission time for LOS calculation
    AND a.dischtime IS NOT NULL -- Ensure valid discharge time for LOS calculation
GROUP BY
    discharge_status
HAVING
    COUNT(*) > 1 -- Ensure at least two records to calculate a meaningful standard deviation
ORDER BY
    discharge_status;