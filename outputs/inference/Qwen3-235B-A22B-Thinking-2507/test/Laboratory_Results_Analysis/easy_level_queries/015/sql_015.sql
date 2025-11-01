WITH pneumonia_admissions AS (
    SELECT DISTINCT 
        a.hadm_id,
        a.admittime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        ON a.hadm_id = d.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE p.gender = 'F'
        AND (
            (d.icd_version = 9 AND (d.icd_code BETWEEN '4800' AND '4869' OR d.icd_code IN ('4870', '4880')))
            OR 
            (d.icd_version = 10 AND d.icd_code >= 'J09' AND d.icd_code < 'J19')
        )
),
creatinine_in_24h AS (
    SELECT 
        pa.hadm_id,
        l.valuenum
    FROM pneumonia_admissions pa
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
        ON pa.hadm_id = l.hadm_id
    WHERE l.itemid = 50912
        AND l.valuenum IS NOT NULL
        AND l.charttime >= pa.admittime
        AND l.charttime < DATETIME_ADD(pa.admittime, INTERVAL 24 HOUR)
),
admission_avg AS (
    SELECT 
        hadm_id,
        AVG(valuenum) AS avg_creat
    FROM creatinine_in_24h
    GROUP BY hadm_id
)
SELECT MIN(avg_creat) AS min_24h_avg_creat
FROM admission_avg;