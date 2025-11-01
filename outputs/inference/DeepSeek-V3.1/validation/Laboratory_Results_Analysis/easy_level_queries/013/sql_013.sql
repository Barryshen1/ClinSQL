SELECT MAX(max_creat) AS max_peak_creatinine_mg_dL
FROM (
    SELECT 
        l.hadm_id,
        MAX(l.valuenum) AS max_creat
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d 
        ON l.itemid = d.itemid
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON l.hadm_id = a.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
        ON a.hadm_id = di.hadm_id
    WHERE 
        p.gender = 'F'
        AND (
            (di.icd_version = 10 AND di.icd_code LIKE 'J44%') 
            OR 
            (di.icd_version = 9 AND di.icd_code LIKE '491%' OR di.icd_code LIKE '492%' OR di.icd_code LIKE '496%')
        )
        AND l.itemid = 50912  -- Serum creatinine
        AND l.valuenum IS NOT NULL
        AND l.valueuom = 'mg/dL'
        AND l.valuenum > 0  -- exclude negative values
        AND l.charttime BETWEEN a.admittime AND a.dischtime  -- during hospitalization
    GROUP BY l.hadm_id
) creat_by_admission;