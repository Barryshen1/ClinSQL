SELECT 
    AVG(DATE_DIFF(stoptime, starttime, DAY)) AS average_duration_days
FROM 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` pt 
ON 
    p.subject_id = pt.subject_id
WHERE 
    pt.gender = 'M' 
    AND pt.anchor_age BETWEEN 43 AND 53
    AND p.drug LIKE '%warfarin%';