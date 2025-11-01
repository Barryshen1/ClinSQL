SELECT PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY los_days) AS percentile_25
FROM (
    SELECT 
        DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON a.hadm_id = d.hadm_id AND d.seq_num = 1
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
        ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
    WHERE 
        p.gender = 'M'
        AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 74 AND 84
        AND di.long_title LIKE '%hemorrhage%'
        AND (di.long_title LIKE '%upper%' 
             OR di.long_title LIKE '%gastric%' 
             OR di.long_title LIKE '%duodenal%' 
             OR di.long_title LIKE '%esophageal%' 
             OR di.long_title LIKE '%gastrointestinal%')
) subquery;