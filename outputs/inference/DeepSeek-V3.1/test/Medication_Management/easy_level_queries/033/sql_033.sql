WITH arbs AS (
    SELECT 
        p.subject_id,
        p.hadm_id,
        p.starttime,
        p.stoptime,
        DATE_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
        ON p.subject_id = pt.subject_id
    WHERE 
        pt.gender = 'F'
        AND pt.anchor_age BETWEEN 77 AND 87
        AND REGEXP_CONTAINS(LOWER(p.drug), r'losartan|valsartan|irbesartan|candesartan|telmisartan|olmesartan|eprosartan|azilsartan')
        AND p.starttime IS NOT NULL
        AND p.stoptime IS NOT NULL
        AND p.stoptime > p.starttime
)
SELECT 
    AVG(duration_days) AS avg_duration_days
FROM arbs;