WITH co AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id, 
        adm.admittime, 
        adm.dischtime
    FROM 
        `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN 
        `physionet-data.mimiciv_3_1_hosp.patients` pat 
        ON adm.subject_id = pat.subject_id
    WHERE 
        pat.gender = 'F'
        AND EXISTS (
            SELECT 1
            FROM 
                `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
            WHERE 
                diag.subject_id = adm.subject_id
                AND diag.hadm_id = adm.hadm_id
                AND (
                    (diag.icd_version = 9 AND diag.icd_code LIKE '491%') 
                    OR (diag.icd_version = 9 AND diag.icd_code LIKE '492%') 
                    OR (diag.icd_version = 9 AND diag.icd_code LIKE '496%')
                    OR (diag.icd_version = 10 AND diag.icd_code LIKE 'J41%') 
                    OR (diag.icd_version = 10 AND diag.icd_code LIKE 'J42%') 
                    OR (diag.icd_version = 10 AND diag.icd_code LIKE 'J43%') 
                    OR (diag.icd_version = 10 AND diag.icd_code LIKE 'J44%')
                )
        )
)
SELECT 
    MAX(creatinine.peak_creatinine) AS max_peak_creatinine
FROM (
    SELECT 
        lab.hadm_id,
        MAX(lab.valuenum) AS peak_creatinine
    FROM 
        `physionet-data.mimiciv_3_1_hosp.labevents` lab
    INNER JOIN 
        co 
        ON lab.hadm_id = co.hadm_id 
        AND lab.subject_id = co.subject_id
    WHERE 
        lab.itemid = 50912  -- Serum creatinine
        AND lab.valuenum IS NOT NULL
        AND lab.valueuom = 'mg/dL'
        AND lab.charttime BETWEEN co.admittime AND co.dischtime
    GROUP BY 
        lab.hadm_id
) creatinine;