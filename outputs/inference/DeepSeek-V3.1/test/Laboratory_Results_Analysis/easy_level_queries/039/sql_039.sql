WITH pneumonia_admissions AS (
    SELECT DISTINCT diag.subject_id, diag.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
    WHERE 
        (d.icd_version = 10 AND d.icd_code LIKE 'J12%' OR d.icd_code LIKE 'J13%' 
         OR d.icd_code LIKE 'J14%' OR d.icd_code LIKE 'J15%' OR d.icd_code LIKE 'J16%' 
         OR d.icd_code LIKE 'J17%' OR d.icd_code LIKE 'J18%')
        OR
        (d.icd_version = 9 AND (d.icd_code LIKE '480%' OR d.icd_code LIKE '481%' 
         OR d.icd_code LIKE '482%' OR d.icd_code LIKE '483%' 
         OR d.icd_code LIKE '485%' OR d.icd_code LIKE '486%'))
),
peak_creatinine AS (
    SELECT 
        l.hadm_id, 
        MAX(l.valuenum) AS peak_creat
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
    INNER JOIN pneumonia_admissions pa 
        ON l.hadm_id = pa.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON l.subject_id = p.subject_id
    WHERE 
        l.itemid = 50912  -- serum creatinine
        AND l.valuenum IS NOT NULL 
        AND l.valuenum > 0
        AND p.gender = 'M'
    GROUP BY l.hadm_id
)
SELECT STDDEV(peak_creat) AS stddev_peak_creatinine
FROM peak_creatinine;