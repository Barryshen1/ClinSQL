SELECT
    a.discharge_location,
    AVG(CAST(DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS FLOAT64)) AS mean_los,
    STDDEV(CAST(DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS FLOAT64)) AS sd_los,
    SUM(CASE WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) <= 7 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS percent_los_le_7
FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.admission_location = 'ED'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
GROUP BY
    a.discharge_location
ORDER BY
    a.discharge_location;