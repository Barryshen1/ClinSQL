WITH pneumonia_females AS (
    SELECT DISTINCT d.subject_id, d.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON d.subject_id = p.subject_id
    WHERE 
        p.gender = 'F'
        AND (
            (d.icd_version = 10 AND d.icd_code LIKE 'J1[2-8]%')
            OR (d.icd_version = 9 AND d.icd_code BETWEEN '480' AND '486')
        )
),
creatinine_24hr AS (
    SELECT 
        pf.subject_id,
        pf.hadm_id,
        AVG(l.valuenum) AS avg_creatinine_24hr
    FROM pneumonia_females pf
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON pf.hadm_id = a.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
        ON pf.hadm_id = l.hadm_id AND pf.subject_id = l.subject_id
    WHERE 
        l.itemid = 50912  -- Serum Creatinine
        AND l.valuenum IS NOT NULL
        AND l.valuenum > 0  -- Exclude non-physiological values
        AND l.charttime BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 24 HOUR)
    GROUP BY pf.subject_id, pf.hadm_id
)
SELECT MIN(avg_creatinine_24hr) AS min_24hr_avg_creatinine
FROM creatinine_24hr;