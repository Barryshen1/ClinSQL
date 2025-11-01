SELECT 
    AVG(DATE_DIFF(a.dischtime, a.admittime, DAY)) AS avg_hospital_los
FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        ON a.hadm_id = d.hadm_id
WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 78 AND 88
    AND d.icd_code IN (
        '410', '410.0', '410.1', '410.2', '410.3', '410.4', '410.5', '410.6', '410.7', '410.8', '410.9',
        '411', '411.0', '411.1', '411.2', '411.3', '411.4', '411.5', '411.6', '411.7', '411.8', '411.9',
        '413', '413.0', '413.1', '413.2', '413.3', '413.4', '413.5', '413.6', '413.7', '413.8', '413.9',
        '414', '414.0', '414.1', '414.2', '414.3', '414.4', '414.5', '414.6', '414.7', '414.8', '414.9'
    )
    AND d.seq_num = 1;  # Primary diagnosis;